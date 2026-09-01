import QtQuick
import QtQuick.Shapes
import Theme

// Disegna un "percorso" di movimento (Animazione): una curva liscia a N
// punti catturati a mano libera durante il drag, a differenza di
// FMFormaLavagna che disegna forme a due punti fissi. Stessa convenzione di
// "punti in pixel LOCALI al campo, il componente si ridimensiona da solo"
// gia' usata li' per p1/p2.
Item {
    id: root

    // Punti grezzi del tracciato, in pixel locali al campo (stesso spazio
    // di p1/p2 in FMFormaLavagna), in ordine di disegno. Servono almeno 2
    // punti perche' compaia qualcosa.
    property var punti: []
    property color colore: "#f4f6fb"
    property bool tratteggiato: false
    property bool selezionato: false
    property int indicePercorso: -1
    property real spessore: 2
    // A differenza delle forme, un percorso non e' modificabile dopo la
    // creazione (elimina e ridisegna): nessun trascinamento, solo
    // selezione/menu contestuale - quindi nessuna property trascinamento*.
    property bool interattivo: true

    signal richiestaSelezione(int indice, bool ctrl)
    signal richiestaMenuContestuale(int indice)

    readonly property real margine: 14
    readonly property real minX: root.punti.length ? Math.min.apply(null, root.punti.map(function(p) { return p.x })) - margine : 0
    readonly property real minY: root.punti.length ? Math.min.apply(null, root.punti.map(function(p) { return p.y })) - margine : 0
    readonly property real maxX: root.punti.length ? Math.max.apply(null, root.punti.map(function(p) { return p.x })) + margine : 1
    readonly property real maxY: root.punti.length ? Math.max.apply(null, root.punti.map(function(p) { return p.y })) + margine : 1

    x: minX
    y: minY
    width: Math.max(1, maxX - minX)
    height: Math.max(1, maxY - minY)

    readonly property var puntiLocali: root.punti.map(function(p) { return {x: p.x - root.x, y: p.y - root.y} })
    readonly property real strokeW: root.spessore + (root.selezionato ? 1 : 0)

    // Tecnica standard "quadratica-attraverso-punti-medi" per una curva
    // liscia attraverso N punti grezzi (freehand smoothing): le "ancore"
    // sono A0=P0, Ai=puntoMedio(Pi,Pi+1) per gli interni, A(N-1)=P(N-1);
    // ogni segmento interno e' una quadratica da Ai ad A(i+1) con P(i+1)
    // come punto di controllo, l'ultimo segmento e' una retta da A(N-2) ad
    // A(N-1). Costruita come UNA sola stringa SVG (numero di segmenti
    // variabile: un Repeater di PathQuad dentro un ShapePath non e'
    // affidabile in QtQuick.Shapes) invece di N elementi Path dichiarativi.
    function costruisciSvgPath(pts) {
        if (pts.length < 2) return ""
        if (pts.length === 2) return "M " + pts[0].x + "," + pts[0].y + " L " + pts[1].x + "," + pts[1].y
        var d = "M " + pts[0].x + "," + pts[0].y
        for (var i = 1; i < pts.length - 1; i++) {
            var mx = (pts[i].x + pts[i + 1].x) / 2
            var my = (pts[i].y + pts[i + 1].y) / 2
            d += " Q " + pts[i].x + "," + pts[i].y + " " + mx + "," + my
        }
        d += " L " + pts[pts.length - 1].x + "," + pts[pts.length - 1].y
        return d
    }
    readonly property string svgPathLocale: costruisciSvgPath(root.puntiLocali)

    // Punta a freccia sull'ultimo tratto (sempre retto, vedi algoritmo
    // sopra): indica il verso della corsa, importante per un percorso
    // molto piu' che per una linea decorativa qualunque.
    readonly property point puntoFinale: root.puntiLocali.length ? root.puntiLocali[root.puntiLocali.length - 1] : Qt.point(0, 0)
    readonly property point puntoPenultimo: root.puntiLocali.length > 1 ? root.puntiLocali[root.puntiLocali.length - 2] : root.puntoFinale
    readonly property real angoloFinale: Math.atan2(puntoFinale.y - puntoPenultimo.y, puntoFinale.x - puntoPenultimo.x)
    readonly property real lunghezzaPunta: 12
    readonly property real aperturaPunta: 0.45
    readonly property real puntaX1: puntoFinale.x - lunghezzaPunta * Math.cos(angoloFinale - aperturaPunta)
    readonly property real puntaY1: puntoFinale.y - lunghezzaPunta * Math.sin(angoloFinale - aperturaPunta)
    readonly property real puntaX2: puntoFinale.x - lunghezzaPunta * Math.cos(angoloFinale + aperturaPunta)
    readonly property real puntaY2: puntoFinale.y - lunghezzaPunta * Math.sin(angoloFinale + aperturaPunta)

    // Rettangolo tratteggiato di selezione, sotto la curva vera e propria.
    Rectangle {
        visible: root.selezionato
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.colors.accent
        radius: Theme.radius.sm
        opacity: 0.6
    }

    Shape {
        anchors.fill: parent
        antialiasing: true
        ShapePath {
            strokeColor: root.colore
            strokeWidth: root.strokeW
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            strokeStyle: root.tratteggiato ? ShapePath.DashLine : ShapePath.SolidLine
            dashPattern: [3, 3]
            PathSvg { path: root.svgPathLocale }
        }
        ShapePath {
            strokeColor: "transparent"
            fillColor: root.colore
            startX: root.puntoFinale.x; startY: root.puntoFinale.y
            PathLine { x: root.puntaX1; y: root.puntaY1 }
            PathLine { x: root.puntaX2; y: root.puntaY2 }
            PathLine { x: root.puntoFinale.x; y: root.puntoFinale.y }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interattivo
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.richiestaSelezione(root.indicePercorso, false)
                root.richiestaMenuContestuale(root.indicePercorso)
            } else {
                root.richiestaSelezione(root.indicePercorso, mouse.modifiers & Qt.ControlModifier)
            }
        }
    }
}
