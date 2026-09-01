import QtQuick
import Theme

// Maniglia di trascinamento da mettere in cima al "background" di ogni
// Popup dell'app: senza, un popup centrato che finisce parzialmente fuori
// dall'area visibile (finestra piccola, piu' popup impilati, taskbar che
// copre il bordo) resta bloccato li', irraggiungibile - segnalato da Luca
// su "Archivio Grafiche Coaching Board" ma vale per qualunque popup.
// Un Popup non e' un Item (e' QQuickPopup): MouseArea.drag.target non si
// applica direttamente, quindi il delta si calcola a mano e si scrive su
// bersaglio.x/y.
Item {
    id: root
    property var bersaglio  // il Popup (QQuickPopup) da spostare

    // Alta quanto il piu' piccolo padding usato dai popup dell'app
    // (Theme.spacing.md = 12): resta sempre sopra al contentItem invece di
    // finirci parzialmente sotto (contentItem e' un fratello disegnato
    // dopo il background, quindi sopra in z-order).
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 11

    Row {
        anchors.centerIn: parent
        spacing: 3
        Repeater {
            model: 3
            delegate: Rectangle {
                width: 3; height: 3; radius: 1.5
                color: areaTrascinamento.containsMouse ? Theme.colors.textSecondary : Theme.colors.textTertiary
            }
        }
    }

    MouseArea {
        id: areaTrascinamento
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeAllCursor
        property real premutoX: 0
        property real premutoY: 0
        onPressed: function(mouse) { premutoX = mouse.x; premutoY = mouse.y }
        onPositionChanged: function(mouse) {
            // hoverEnabled (per l'effetto sui puntini al passaggio del
            // mouse) fa scattare onPositionChanged anche senza click: senza
            // "pressed", un semplice passaggio del mouse applicherebbe un
            // delta calcolato da premutoX/Y ancora a 0 (mai impostato da
            // onPressed), spostando il popup con un salto a vuoto.
            if (!areaTrascinamento.pressed) return
            if (!root.bersaglio) return
            root.bersaglio.x += mouse.x - premutoX
            root.bersaglio.y += mouse.y - premutoY
        }
    }
}
