import QtQuick
import QtQuick.Shapes
import Theme

// Disegna una "forma" dello strumento Disegna della Coaching Board: freccia,
// linea, rettangolo vuoto/pieno, ellisse vuota/piena - stessa dotazione
// dello strumento "Disegna" del vecchio editor (interfaccia_coaching_board.py),
// completamente assente nella ricostruzione QML fino a questa sessione.
// A differenza degli altri elementi (un centro + una dimensione fissa),
// una forma e' definita da due punti (p1/p2) in pixel LOCALI al campo:
// il componente si ridimensiona da solo per contenerli entrambi.
Item {
    id: root

    property point p1: Qt.point(0, 0)
    property point p2: Qt.point(80, 80)
    property string tipo: "linea"
    property color colore: "#f4f6fb"
    property bool tratteggiato: false
    property bool selezionato: false
    property int indiceForma: -1
    // Spessore del tratto in pixel (assottigliato di default rispetto al
    // vecchio 3 fisso). Personalizzabile per elemento, anche dopo il
    // disegno - si applica automaticamente a linee, frecce (dritte e
    // curve), rettangoli ed ellissi perche' tutte condividono strokeW.
    property real spessore: 2
    // Spostamento perpendicolare del punto medio della curva, come frazione
    // della lunghezza del segmento p1-p2 (0 = dritta). Solo per
    // lineaCurva/frecciaCurva; ignorata per gli altri tipi.
    property real curvatura: 0
    readonly property bool eCurva: root.tipo === "lineaCurva" || root.tipo === "frecciaCurva"

    signal curvaturaCambiata(int indice, real curvatura)
    // Disattivata mentre uno strumento di disegno e' attivo: altrimenti
    // trascinare per disegnare una nuova forma esattamente sopra una forma
    // gia' esistente la sposterebbe invece di crearne una nuova.
    property bool interattivo: true
    // Disattiva solo l'accumulo del trascinamento individuale (click e
    // click destro restano attivi): usata dal chiamante quando questa forma
    // e' parte di una selezione multipla che si sta trascinando in gruppo,
    // per evitare due spostamenti indipendenti sulla stessa forma.
    property bool trascinamentoSospeso: false

    // Offset di trascinamento applicato in anteprima durante il drag (in
    // pixel locali al campo): il dato vero (p1/p2) si aggiorna solo al
    // rilascio, via il segnale spostata, per fare un'unica scrittura sul
    // ViewModel invece di una ad ogni pixel di movimento.
    property real trascDx: 0
    property real trascDy: 0

    signal richiestaSelezione(int indice, bool ctrl)
    signal spostata(int indice, real dxPx, real dyPx)
    signal richiestaMenuContestuale(int indice)

    readonly property point p1Eff: Qt.point(p1.x + trascDx, p1.y + trascDy)
    readonly property point p2Eff: Qt.point(p2.x + trascDx, p2.y + trascDy)

    readonly property real margine: 14
    readonly property real minX: Math.min(p1Eff.x, p2Eff.x) - margine
    readonly property real minY: Math.min(p1Eff.y, p2Eff.y) - margine

    x: minX
    y: minY
    width: Math.max(1, Math.max(p1Eff.x, p2Eff.x) - minX + margine)
    height: Math.max(1, Math.max(p1Eff.y, p2Eff.y) - minY + margine)

    readonly property real lx1: p1Eff.x - root.x
    readonly property real ly1: p1Eff.y - root.y
    readonly property real lx2: p2Eff.x - root.x
    readonly property real ly2: p2Eff.y - root.y
    readonly property real strokeW: root.spessore + (root.selezionato ? 1 : 0)

    // Geometria di rettangolo/ellisse calcolata qui su root (non su
    // ShapePath, ne' con "parent." dentro PathLine/PathArc): gli elementi
    // di un Path (PathLine, PathArc, ...) non sono Item e non "vedono" ne'
    // il parent visivo ne' le property dichiarate sul ShapePath che li
    // contiene - solo un riferimento per id (root.xxx) risolve sempre,
    // qualunque sia la profondita' di annidamento. Con "parent.xxx" o un
    // nome non qualificato il binding falliva silenziosamente (o con
    // "ReferenceError: ... is not defined") e la forma non disegnava
    // nulla: bug segnalato da Luca su rettangolo vuoto/pieno ed ellisse
    // vuota/piena.
    readonly property real rettLeft: Math.min(lx1, lx2)
    readonly property real rettTop: Math.min(ly1, ly2)
    readonly property real rettRight: Math.max(lx1, lx2)
    readonly property real rettBottom: Math.max(ly1, ly2)
    readonly property real ellisseCx: (lx1 + lx2) / 2
    readonly property real ellisseCy: (ly1 + ly2) / 2
    readonly property real ellisseRx: Math.max(4, Math.abs(lx2 - lx1) / 2)
    readonly property real ellisseRy: Math.max(4, Math.abs(ly2 - ly1) / 2)

    // Rettangolo tratteggiato di selezione, sotto la forma vera e propria.
    Rectangle {
        visible: root.selezionato
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.colors.accent
        radius: Theme.radius.sm
        opacity: 0.6
    }

    Loader {
        anchors.fill: parent
        sourceComponent: {
            if (root.tipo === "linea" || root.tipo === "freccia") return compLinea
            if (root.tipo === "lineaCurva" || root.tipo === "frecciaCurva") return compCurva
            if (root.tipo === "rettVuoto" || root.tipo === "rettPieno") return compRettangolo
            if (root.tipo === "ellisseV" || root.tipo === "ellisseP") return compEllisse
            return null
        }
    }

    // Maniglia di curvatura: trascinabile solo quando la forma e' selezionata,
    // regola root.curvatura in anteprima locale (nessuna scrittura sul
    // ViewModel finche' non si rilascia, stesso principio del trascinamento
    // dell'intera forma sopra).
    Item {
        id: manigliaCurvatura
        visible: root.selezionato && root.eCurva
        readonly property real midX: (root.lx1 + root.lx2) / 2
        readonly property real midY: (root.ly1 + root.ly2) / 2
        readonly property real dx: root.lx2 - root.lx1
        readonly property real dy: root.ly2 - root.ly1
        readonly property real lunghezza: Math.max(1, Math.sqrt(dx * dx + dy * dy))
        readonly property real perpX: -dy / lunghezza
        readonly property real perpY: dx / lunghezza
        property bool trascinando: false
        property real curvaturaAnteprima: root.curvatura
        readonly property real curvaturaEff: trascinando ? curvaturaAnteprima : root.curvatura
        readonly property real handleX: midX + perpX * curvaturaEff * lunghezza
        readonly property real handleY: midY + perpY * curvaturaEff * lunghezza

        x: handleX - 8
        y: handleY - 8
        width: 16
        height: 16
        z: 10

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.colors.accent
            border.width: 2
            border.color: "#ffffff"
        }

        MouseArea {
            id: trascinamento
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // Non si usa drag.target (romperebbe per sempre il binding x/y
            // della maniglia su handleX/handleY): si mappano le coordinate
            // del mouse nello spazio locale di root ad ogni evento (assoluto,
            // non un delta accumulato) e si ricava la curvatura da li'.
            onPressed: manigliaCurvatura.trascinando = true
            onPositionChanged: function(mouse) {
                if (!manigliaCurvatura.trascinando) return
                var pt = trascinamento.mapToItem(root, mouse.x, mouse.y)
                var offset = (pt.x - manigliaCurvatura.midX) * manigliaCurvatura.perpX + (pt.y - manigliaCurvatura.midY) * manigliaCurvatura.perpY
                manigliaCurvatura.curvaturaAnteprima = Math.max(-1, Math.min(1, offset / manigliaCurvatura.lunghezza))
            }
            onReleased: {
                manigliaCurvatura.trascinando = false
                root.curvaturaCambiata(root.indiceForma, manigliaCurvatura.curvaturaAnteprima)
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.interattivo
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real pressX: 0
        property real pressY: 0
        onPressed: function(mouse) { pressX = mouse.x; pressY = mouse.y }
        onPositionChanged: function(mouse) {
            // ATTENZIONE: qui non si puo' assegnare trascDx = mouse.x - pressX.
            // Questo Item si sposta insieme al trascinamento (root.x dipende
            // da trascDx), quindi la MouseArea si sposta con lui: ad ogni
            // evento le coordinate locali del mouse si "riallineano" verso
            // pressX, e riassegnare azzererebbe l'incremento gia' applicato
            // (il trascinamento si blocca al primo movimento). Accumulando
            // con += l'incremento LOCALE di ogni evento si somma
            // correttamente allo spostamento totale.
            if (root.trascinamentoSospeso) return
            if (pressed && (mouse.buttons & Qt.LeftButton)) {
                root.trascDx += mouse.x - pressX
                root.trascDy += mouse.y - pressY
            }
        }
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                root.richiestaSelezione(root.indiceForma, false)
                root.richiestaMenuContestuale(root.indiceForma)
            } else {
                root.richiestaSelezione(root.indiceForma, mouse.modifiers & Qt.ControlModifier)
            }
        }
        onReleased: {
            if (root.trascDx !== 0 || root.trascDy !== 0) {
                root.spostata(root.indiceForma, root.trascDx, root.trascDy)
            }
            root.trascDx = 0
            root.trascDy = 0
        }
    }

    Component {
        id: compLinea
        Item {
            id: contenitoreLinea
            anchors.fill: parent
            readonly property real angolo: Math.atan2(root.ly2 - root.ly1, root.lx2 - root.lx1)
            readonly property real lunghezzaPunta: 14
            readonly property real aperturaPunta: 0.45
            readonly property real puntaX1: root.lx2 - lunghezzaPunta * Math.cos(angolo - aperturaPunta)
            readonly property real puntaY1: root.ly2 - lunghezzaPunta * Math.sin(angolo - aperturaPunta)
            readonly property real puntaX2: root.lx2 - lunghezzaPunta * Math.cos(angolo + aperturaPunta)
            readonly property real puntaY2: root.ly2 - lunghezzaPunta * Math.sin(angolo + aperturaPunta)

            Shape {
                anchors.fill: parent
                antialiasing: true
                ShapePath {
                    strokeColor: root.colore
                    strokeWidth: root.strokeW
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    strokeStyle: root.tratteggiato ? ShapePath.DashLine : ShapePath.SolidLine
                    dashPattern: [3, 3]
                    startX: root.lx1; startY: root.ly1
                    PathLine { x: root.lx2; y: root.ly2 }
                }
                ShapePath {
                    // ShapePath non ha una property "visible": quando non e'
                    // una freccia si rende invisibile lasciando la geometria
                    // (altrimenti innocua) ma azzerando il riempimento.
                    strokeColor: "transparent"
                    fillColor: root.tipo === "freccia" ? root.colore : "transparent"
                    startX: root.lx2; startY: root.ly2
                    PathLine { x: contenitoreLinea.puntaX1; y: contenitoreLinea.puntaY1 }
                    PathLine { x: contenitoreLinea.puntaX2; y: contenitoreLinea.puntaY2 }
                    PathLine { x: root.lx2; y: root.ly2 }
                }
            }
        }
    }

    Component {
        id: compCurva
        Item {
            id: contenitoreCurva
            anchors.fill: parent
            readonly property real midX: (root.lx1 + root.lx2) / 2
            readonly property real midY: (root.ly1 + root.ly2) / 2
            readonly property real dx: root.lx2 - root.lx1
            readonly property real dy: root.ly2 - root.ly1
            readonly property real lunghezza: Math.max(1, Math.sqrt(dx * dx + dy * dy))
            readonly property real perpX: -dy / lunghezza
            readonly property real perpY: dx / lunghezza
            // Punto di controllo della quadratica: il punto medio VISIBILE
            // della curva e' a meta' strada tra il punto medio del segmento
            // dritto e il punto di controllo, quindi per ottenere uno
            // spostamento del punto medio pari a "curvatura * lunghezza" il
            // controllo va messo al doppio di quella distanza.
            readonly property real controlX: midX + perpX * root.curvatura * lunghezza * 2
            readonly property real controlY: midY + perpY * root.curvatura * lunghezza * 2
            // Tangente della curva nel punto finale (derivata della
            // quadratica in t=1): usata per orientare la punta della
            // freccia, che con una curva pronunciata non punta piu' dritta
            // verso p1 come nella freccia dritta.
            readonly property real angolo: Math.atan2(root.ly2 - controlY, root.lx2 - controlX)
            readonly property real lunghezzaPunta: 14
            readonly property real aperturaPunta: 0.45
            readonly property real puntaX1: root.lx2 - lunghezzaPunta * Math.cos(angolo - aperturaPunta)
            readonly property real puntaY1: root.ly2 - lunghezzaPunta * Math.sin(angolo - aperturaPunta)
            readonly property real puntaX2: root.lx2 - lunghezzaPunta * Math.cos(angolo + aperturaPunta)
            readonly property real puntaY2: root.ly2 - lunghezzaPunta * Math.sin(angolo + aperturaPunta)

            Shape {
                anchors.fill: parent
                antialiasing: true
                ShapePath {
                    strokeColor: root.colore
                    strokeWidth: root.strokeW
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    strokeStyle: root.tratteggiato ? ShapePath.DashLine : ShapePath.SolidLine
                    dashPattern: [3, 3]
                    startX: root.lx1; startY: root.ly1
                    PathQuad { x: root.lx2; y: root.ly2; controlX: contenitoreCurva.controlX; controlY: contenitoreCurva.controlY }
                }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: root.tipo === "frecciaCurva" ? root.colore : "transparent"
                    startX: root.lx2; startY: root.ly2
                    PathLine { x: contenitoreCurva.puntaX1; y: contenitoreCurva.puntaY1 }
                    PathLine { x: contenitoreCurva.puntaX2; y: contenitoreCurva.puntaY2 }
                    PathLine { x: root.lx2; y: root.ly2 }
                }
            }
        }
    }

    Component {
        id: compRettangolo
        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeColor: root.colore
                strokeWidth: root.strokeW
                fillColor: root.tipo === "rettPieno" ? Qt.rgba(root.colore.r, root.colore.g, root.colore.b, 0.35) : "transparent"
                strokeStyle: root.tratteggiato ? ShapePath.DashLine : ShapePath.SolidLine
                dashPattern: [3, 3]
                startX: root.rettLeft; startY: root.rettTop
                PathLine { x: root.rettRight; y: root.rettTop }
                PathLine { x: root.rettRight; y: root.rettBottom }
                PathLine { x: root.rettLeft; y: root.rettBottom }
                PathLine { x: root.rettLeft; y: root.rettTop }
            }
        }
    }

    Component {
        id: compEllisse
        Shape {
            anchors.fill: parent
            antialiasing: true
            ShapePath {
                strokeColor: root.colore
                strokeWidth: root.strokeW
                fillColor: root.tipo === "ellisseP" ? Qt.rgba(root.colore.r, root.colore.g, root.colore.b, 0.35) : "transparent"
                strokeStyle: root.tratteggiato ? ShapePath.DashLine : ShapePath.SolidLine
                dashPattern: [3, 3]
                startX: root.ellisseCx - root.ellisseRx; startY: root.ellisseCy
                PathArc { x: root.ellisseCx + root.ellisseRx; y: root.ellisseCy; radiusX: root.ellisseRx; radiusY: root.ellisseRy; useLargeArc: true }
                PathArc { x: root.ellisseCx - root.ellisseRx; y: root.ellisseCy; radiusX: root.ellisseRx; radiusY: root.ellisseRy; useLargeArc: true }
            }
        }
    }
}
