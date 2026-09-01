import QtQuick

// Conetto colorabile: stessa tecnica di FMGiocatoreForma (maschera
// bianca-su-trasparente dell'intera sagoma + Canvas con
// globalCompositeOperation "source-in" + fillRect), qui con un'unica
// maschera/colore dato che l'icona non ha parti distinte da colorare
// separatamente (a differenza di maglia/pantaloncini del giocatore).
Item {
    id: root

    property color colore: "#f5a45c"

    readonly property real assetW: imgMaschera.sourceSize.width > 0 ? imgMaschera.sourceSize.width : 1
    readonly property real assetH: imgMaschera.sourceSize.height > 0 ? imgMaschera.sourceSize.height : 1
    readonly property real scalaFit: Math.min(width / assetW, height / assetH)
    readonly property real drawW: assetW * scalaFit
    readonly property real drawH: assetH * scalaFit
    readonly property real drawX: (width - drawW) / 2
    readonly property real drawY: (height - drawH) / 2

    Image {
        id: imgMaschera
        source: Qt.resolvedUrl("../../assets/board/conetto_mask.png")
        visible: false
        onStatusChanged: if (status === Image.Ready) tela.requestPaint()
    }

    Canvas {
        id: tela
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (imgMaschera.status !== Image.Ready) return
            ctx.drawImage(imgMaschera, root.drawX, root.drawY, root.drawW, root.drawH)
            ctx.globalCompositeOperation = "source-in"
            ctx.fillStyle = root.colore
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "source-over"
        }
    }

    onWidthChanged: tela.requestPaint()
    onHeightChanged: tela.requestPaint()
    onColoreChanged: tela.requestPaint()
    Component.onCompleted: tela.requestPaint()
}
