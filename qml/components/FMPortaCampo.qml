import QtQuick

// Porta con rete visibile: prima l'elemento "porta" piazzabile sul campo era
// un semplice bordo trasparente 2px (quasi invisibile una volta rimpicciolito
// nell'anteprima della lavagna, es. il thumbnail di FMEditorImmagineEsercizio
// generato da grabToImage). Qui palo/traversa sono piu' spessi e un mesh di
// rete stilizzata riempie l'interno, cosi' resta leggibile anche a ~140px.
Item {
    id: root

    property color colore: "#ffffff"

    Canvas {
        id: tela
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height
            var spessore = Math.max(2, Math.min(w, h) * 0.06)

            ctx.strokeStyle = root.colore
            ctx.lineWidth = spessore
            ctx.strokeRect(spessore / 2, spessore / 2, w - spessore, h - spessore)

            // Rete: griglia diagonale sottile, piu' rada dei pali cosi' resta
            // leggibile come "rete" anche a dimensioni ridotte.
            ctx.lineWidth = Math.max(0.6, spessore * 0.25)
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.55)
            var passo = Math.max(6, Math.min(w, h) * 0.22)
            var x, y
            ctx.beginPath()
            for (x = -h; x < w; x += passo) {
                ctx.moveTo(x, 0)
                ctx.lineTo(x + h, h)
            }
            for (x = 0; x < w + h; x += passo) {
                ctx.moveTo(x, 0)
                ctx.lineTo(x - h, h)
            }
            ctx.stroke()
        }
    }

    onWidthChanged: tela.requestPaint()
    onHeightChanged: tela.requestPaint()
    onColoreChanged: tela.requestPaint()
    Component.onCompleted: tela.requestPaint()
}
