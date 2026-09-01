import QtQuick

// Sagoma giocatore basata su asset raster (disegno a china fornito da Luca,
// derivato da "Giocatore.png" in raw/Progetto FC Manager/Lavagna tattica_basi
// grafiche/), non piu' disegnata a Canvas vettoriale. Tre livelli impilati
// alla stessa geometria (drawX/drawY/drawW/drawH, aspect-fit centrato):
//  1. giocatore_maglia.png - maschera bianca-su-trasparente della sola area
//     maglia, ricolorata con "colore" (Canvas + source-in).
//  2. giocatore_pantaloncini.png - stessa tecnica per i pantaloncini,
//     ricolorati con "coloreContorno".
//  3. giocatore_base.png - disegno originale con sfondo trasparente e "buchi"
//     trasparenti esattamente dove le due maschere sopra sono opache (resto
//     del disegno: testa, capelli, braccia, gambe, calzini, scarpe - fissi,
//     non ricolorabili), sopra a tutto cosi' il contorno resta netto.
// Le tre immagini condividono lo stesso ritaglio/dimensione in pixel (stesso
// bounding box calcolato in fase di generazione asset), quindi usare la
// stessa geometria per tutte e tre le mantiene perfettamente allineate.
Item {
    id: root

    property color colore: "#3d5afe"
    property color coloreContorno: "#ffffff"
    property bool selezionato: false

    readonly property real assetW: imgBase.sourceSize.width > 0 ? imgBase.sourceSize.width : 1
    readonly property real assetH: imgBase.sourceSize.height > 0 ? imgBase.sourceSize.height : 1
    readonly property real scalaFit: Math.min(width / assetW, height / assetH)
    readonly property real drawW: assetW * scalaFit
    readonly property real drawH: assetH * scalaFit
    readonly property real drawX: (width - drawW) / 2
    readonly property real drawY: (height - drawH) / 2

    Image {
        id: imgMaglia
        source: Qt.resolvedUrl("../../assets/board/giocatore_maglia.png")
        visible: false
        onStatusChanged: if (status === Image.Ready) telaMaglia.requestPaint()
    }
    Image {
        id: imgPantaloncini
        source: Qt.resolvedUrl("../../assets/board/giocatore_pantaloncini.png")
        visible: false
        onStatusChanged: if (status === Image.Ready) telaPantaloncini.requestPaint()
    }
    Image {
        id: imgBase
        source: Qt.resolvedUrl("../../assets/board/giocatore_base.png")
        visible: false
    }

    Canvas {
        id: telaMaglia
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (imgMaglia.status !== Image.Ready) return
            ctx.drawImage(imgMaglia, root.drawX, root.drawY, root.drawW, root.drawH)
            ctx.globalCompositeOperation = "source-in"
            ctx.fillStyle = root.colore
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "source-over"
        }
    }

    Canvas {
        id: telaPantaloncini
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            if (imgPantaloncini.status !== Image.Ready) return
            ctx.drawImage(imgPantaloncini, root.drawX, root.drawY, root.drawW, root.drawH)
            ctx.globalCompositeOperation = "source-in"
            ctx.fillStyle = root.coloreContorno
            ctx.fillRect(0, 0, width, height)
            ctx.globalCompositeOperation = "source-over"
        }
    }

    Image {
        x: root.drawX
        y: root.drawY
        width: root.drawW
        height: root.drawH
        source: imgBase.source
        smooth: true
    }

    Rectangle {
        visible: root.selezionato
        x: root.drawX - 4
        y: root.drawY - 4
        width: root.drawW + 8
        height: root.drawH + 8
        radius: 6
        color: "transparent"
        border.color: "#ffd400"
        border.width: 2
        opacity: 0.85
    }

    function _ridisegna() {
        telaMaglia.requestPaint()
        telaPantaloncini.requestPaint()
    }

    onWidthChanged: _ridisegna()
    onHeightChanged: _ridisegna()
    onColoreChanged: telaMaglia.requestPaint()
    onColoreContornoChanged: telaPantaloncini.requestPaint()
    Component.onCompleted: _ridisegna()
}
