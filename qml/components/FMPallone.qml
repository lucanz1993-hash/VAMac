import QtQuick

// Pallone: icona reale fornita da Luca (assets/board/pallone.png, generata da
// soccer-ball-vector-icon.jpg con lo sfondo bianco reso trasparente via
// flood-fill, preservando i pentagoni bianchi interni) al posto del pallone
// disegnato a mano su Canvas usato prima.
Item {
    id: root

    Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("../../assets/board/pallone.png")
        fillMode: Image.PreserveAspectFit
        smooth: true
    }
}
