import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Dialogs
import Theme
import "../components"

Item {
    id: root
    focus: true

    property int selezionato: -1        // ultimo elemento selezionato (usato dal pannello "Personalizza")
    property var selezionati: []        // indici in selezione multipla (Ctrl+click o lazo)
    property int indiceMenuContestuale: -1

    // Trascinamento di gruppo: quando si trascina un elemento che fa parte
    // di una selezione multipla, tutti gli elementi selezionati si spostano
    // insieme. Offset in pixel locali al campo, applicato in anteprima da
    // ogni delegate selezionato (icone e forme) finche' non si rilascia,
    // poi scritto una sola volta sul ViewModel (vedi spostaElementi).
    property bool trascinandoMultiplo: false
    property real trascinamentoDx: 0
    property real trascinamentoDy: 0

    // Ultimo colore scelto per ciascuna squadra: usato sia come default per
    // i nuovi giocatori aggiunti (+ Sq 1/+ Sq 2), sia per ricolorare in blocco
    // tutti i giocatori gia' piazzati della stessa squadra (vedi sezione
    // "Colori squadre" e impostaColoreMagliaSquadra/impostaColoreCalzeSquadra
    // sul ViewModel). I colori effettivi di ogni giocatore restano salvati
    // sull'elemento stesso; questi sono solo il default per i PROSSIMI nuovi
    // giocatori - persistiti tra sessioni (leggiImpostazione/
    // scriviImpostazione sul ViewModel, stesso QSettings di ThemeManager)
    // cosi' non vanno reimpostati ogni volta che si apre una lavagna.
    property color coloreMagliaSquadraA: "#e0544f"
    property color coloreCalzeSquadraA: "#ffffff"
    property color coloreMagliaSquadraB: "#3d5afe"
    property color coloreCalzeSquadraB: "#ffffff"

    Component.onCompleted: {
        var a1 = coachingBoardVM.leggiImpostazione("coloreMagliaSquadraA")
        var a2 = coachingBoardVM.leggiImpostazione("coloreCalzeSquadraA")
        var b1 = coachingBoardVM.leggiImpostazione("coloreMagliaSquadraB")
        var b2 = coachingBoardVM.leggiImpostazione("coloreCalzeSquadraB")
        var dc = coachingBoardVM.leggiImpostazione("coloreDisegno")
        var ds = coachingBoardVM.leggiImpostazione("spessoreDisegno")
        if (a1 !== "") root.coloreMagliaSquadraA = a1
        if (a2 !== "") root.coloreCalzeSquadraA = a2
        if (b1 !== "") root.coloreMagliaSquadraB = b1
        if (b2 !== "") root.coloreCalzeSquadraB = b2
        if (dc !== "") root.coloreDisegnoAttivo = dc
        if (ds !== "") root.spessoreDisegnoAttivo = parseFloat(ds)
    }

    // Il campo deve occupare la maggior parte dello schermo invece di stare
    // a dimensione fissa (700x460): si calcola una scala dallo spazio
    // realmente disponibile nel riquadro a destra della sidebar, mantenendo
    // il rapporto 700:460 - ridimensionare la finestra ridimensiona il campo,
    // dato che sono binding reattivi su flickableCampo.width/height.
    readonly property real areaDisponibileW: flickableCampo.width - Theme.spacing.xl * 2
    readonly property real areaDisponibileH: flickableCampo.height - Theme.spacing.xl * 2
    // In modalita' "meta" il campo visualizzato e' 460x350 (vedi width/height
    // di campoTattico piu' sotto), non 700x460: calcolare scalaCampo sempre
    // sul rapporto del campo intero lo faceva stare piu' piccolo del
    // necessario, con spazio vuoto ai lati - ora la scala si adatta alle
    // dimensioni reali della modalita' attiva cosi' riempie l'ampiezza
    // disponibile in entrambi i casi.
    readonly property bool campoDimensioneMeta: coachingBoardVM.modalitaCampo === "meta" || coachingBoardVM.modalitaCampo === "nessuna"
    readonly property real scalaCampo: root.campoDimensioneMeta
        ? Math.max(0.6, Math.min(root.areaDisponibileW / 460, root.areaDisponibileH / 350))
        : Math.max(0.6, Math.min(root.areaDisponibileW / 700, root.areaDisponibileH / 460))
    readonly property real larghezzaCampo: 700 * root.scalaCampo
    readonly property real altezzaCampo: 460 * root.scalaCampo

    // Sidebar sinistra ridimensionabile a mano (Luca: puo' essere allargata
    // fino a 2x - il campo non ne risente perche' scalaCampo (sopra) e'
    // quasi sempre vincolato da areaDisponibileH/barraInferiore, non da
    // areaDisponibileW: il min() nella formula sceglie il rapporto piu'
    // piccolo, quindi finche' la larghezza resta il fattore non-vincolante
    // allargare la sidebar e' "gratis" per la dimensione del campo).
    // Solo dimensione laterale: l'altezza resta sempre parent.height.
    readonly property int larghezzaSidebarMinima: 230
    readonly property int larghezzaSidebarMassima: larghezzaSidebarMinima * 2
    property int larghezzaSidebar: larghezzaSidebarMinima

    // Barra inferiore (comandi aggiungi elementi/strumenti disegno)
    // ridimensionabile a mano allo stesso modo: di default resta alla sua
    // altezza naturale (contenutoInferiore.implicitHeight, invariata
    // rispetto a prima), ma si puo' trascinare piu' bassa - fino a meno
    // della meta' - per lasciare piu' spazio verticale al campo, con
    // scroll verticale sul contenuto che non ci sta piu'.
    readonly property real altezzaBarraInferioreMassima: contenutoInferiore.implicitHeight
    readonly property real altezzaBarraInferioreMinima: Math.max(90, altezzaBarraInferioreMassima * 0.4)
    property real altezzaBarraInferiore: altezzaBarraInferioreMassima

    // Dimensioni del popup "Animazione" (vedi piu' sotto, popupAnimazione),
    // regolabili trascinando la maniglia d'angolo in basso a destra - stesso
    // schema min/attuale/max delle altre due dimensioni ridimensionabili
    // qui sopra.
    readonly property int larghezzaPopupAnimazioneMinima: 360
    readonly property int larghezzaPopupAnimazioneMassima: 900
    property int larghezzaPopupAnimazione: 480
    readonly property int altezzaPopupAnimazioneMinima: 240
    readonly property int altezzaPopupAnimazioneMassima: 800
    property int altezzaPopupAnimazione: 560

    // Costanti delle marcature decorative (area di rigore/area piccola/segno
    // porta/cerchio centrocampo), scalate insieme al campo cosi' restano
    // proporzionate qualunque sia la dimensione finale - prima erano pixel
    // assoluti validi solo per il campo a dimensione fissa.
    readonly property real boxProfondita: 110 * root.scalaCampo
    readonly property real boxSpan: 260 * root.scalaCampo
    readonly property real areaPiccolaProfondita: 45 * root.scalaCampo
    readonly property real areaPiccolaSpan: 140 * root.scalaCampo
    readonly property real segnoPortaProfondita: 8 * 1.25 * root.scalaCampo
    readonly property real segnoPortaSpan: 50 * 1.25 * root.scalaCampo
    readonly property real arcoAngoloRaggio: 61 * root.scalaCampo
    readonly property real cerchioCentrocampoRaggio: 45 * root.scalaCampo
    // Margine attorno al campo (in "areaEsportabile" piu' sotto) che da'
    // spazio ai segni di porta, i quali sporgono oltre il rettangolo del
    // campo vero e proprio - senza, grabToImage() li taglierebbe fuori.
    readonly property real margineEsportazione: root.segnoPortaProfondita + 4

    readonly property var tipiForma: ["freccia", "linea", "rettVuoto", "rettPieno", "ellisseV", "ellisseP", "lineaCurva", "frecciaCurva"]
    function eForma(tipo) { return root.tipiForma.indexOf(tipo) !== -1 }

    // Strumento di disegno attivo ("" = seleziona/sposta come prima).
    property string strumentoAttivo: ""
    property bool tratteggiatoAttivo: false
    property color coloreDisegnoAttivo: "#f4f6fb"
    property real spessoreDisegnoAttivo: 2
    property bool disegnandoForma: false
    property point disegnoInizio: Qt.point(0, 0)
    property point disegnoFine: Qt.point(0, 0)

    // --- Animazione: disegno di un percorso di movimento ---
    // Il gesto parte SOLO da un giocatore/pallone (vedi la MouseArea del
    // delegate elemento piu' sotto, non da questa area vuota del campo):
    // punti campionati in pixel LOCALI al campo, con una soglia minima per
    // non accumulare migliaia di campioni quasi duplicati su un drag lungo.
    property bool disegnandoPercorso: false
    property var percorsoPuntiAnteprima: []
    property int percorsoAncoraId: -1
    readonly property real distanzaMinimaCampionamento: 6

    // --- Animazione: stato di riproduzione, SOLO qui (mai sul ViewModel,
    // mai persistito): quando modalitaAnimazione e' false ogni marcatore
    // resta esattamente dov'e' oggi, zero rischio per chi non usa la
    // funzione (vedi posizioneEffettiva sul delegate elemento).
    property bool modalitaAnimazione: false
    property bool inRiproduzione: false
    property real progressoAnimazione: 0.0
    // {a,b,pallone}: oggetto in una property var, la mutazione in-place NON
    // notifica il binding - ogni toggle deve riassegnare l'intero oggetto
    // (vedi impostaVisibilitaSquadra sotto).
    property var squadreVisibili: ({a: true, b: true, pallone: true})
    // Calcolata, mai salvata: max(ritardo+durata) su tutti i percorsi -
    // evita un controllo "durata totale" separato da tenere sincronizzato
    // ogni volta che l'utente regola un ritardo/durata di un percorso.
    readonly property real durataTotaleAnimazione: {
        var massimo = 0
        for (var i = 0; i < coachingBoardVM.elementi.length; i++) {
            var el = coachingBoardVM.elementi[i]
            if (el.tipo === "percorso") massimo = Math.max(massimo, el.ritardo + el.durata)
        }
        return massimo
    }

    // --- Animazione: esportazione GIF ---
    property bool esportazioneInCorso: false
    property int fotogrammaEsportazione: 0
    property int totaleFotogrammiEsportazione: 0
    property var _fotogrammiCatturati: []
    property string _destinazioneEsportazione: ""
    readonly property real fpsEsportazione: 12

    // Selezione multipla a rettangolo: premi-trascina su area vuota del
    // campo (nessuno strumento di disegno attivo) per selezionare tutti gli
    // elementi il cui centro ricade dentro il rettangolo tracciato.
    property bool selezionandoRettangolo: false
    property point selezioneInizio: Qt.point(0, 0)
    property point selezioneFine: Qt.point(0, 0)

    function isSelezionato(i) { return root.selezionati.indexOf(i) !== -1 }
    function toggleSelezione(i, ctrl) {
        if (ctrl) {
            var lista = root.selezionati.slice()
            var pos = lista.indexOf(i)
            if (pos === -1) lista.push(i); else lista.splice(pos, 1)
            root.selezionati = lista
            root.selezionato = i
        } else {
            root.selezionati = [i]
            root.selezionato = i
        }
    }
    function deselezionaTutto() { root.selezionati = []; root.selezionato = -1 }

    // Lo stile Basic non riposiziona da solo un Menu che aprirebbe fuori
    // dalla finestra: un elemento vicino al bordo del campo apriva il menu
    // contestuale parzialmente o del tutto fuori dall'area visibile. Si
    // blocca il punto dentro i bordi dell'Overlay, stesso principio gia'
    // usato per centrare i Popup di questo programma su Overlay.overlay.
    function apriMenuContestualeA(puntoOverlay) {
        var overlay = Overlay.overlay
        if (overlay && puntoOverlay) {
            menuContestuale.parent = overlay
            menuContestuale.x = Math.max(0, Math.min(puntoOverlay.x, overlay.width - menuContestuale.implicitWidth))
            menuContestuale.y = Math.max(0, Math.min(puntoOverlay.y, overlay.height - menuContestuale.implicitHeight))
        }
        menuContestuale.popup()
    }
    function elementoSelezionato() {
        if (root.selezionato < 0 || root.selezionato >= coachingBoardVM.elementi.length) return null
        return coachingBoardVM.elementi[root.selezionato]
    }

    function impostaVisibilitaSquadra(chiave, valore) {
        var s = root.squadreVisibili
        root.squadreVisibili = {a: chiave === "a" ? valore : s.a, b: chiave === "b" ? valore : s.b, pallone: chiave === "pallone" ? valore : s.pallone}
    }

    function urlAPercorso(url) {
        var s = url.toString()
        var prefisso = "file:///"
        if (s.indexOf(prefisso) === 0) s = s.substring(prefisso.length)
        return decodeURIComponent(s)
    }

    // Converte i punti normalizzati (0-1) di un percorso in pixel LOCALI al
    // campo - stesso spazio di p1/p2 in FMFormaLavagna/FMPercorsoLavagna.
    function puntiPixelPercorso(punti) {
        return punti.map(function(p) { return {x: p.x * campoTattico.width, y: p.y * campoTattico.height} })
    }

    // Scomposizione in segmenti IDENTICA a FMPercorsoLavagna.costruisciSvgPath
    // (stesse ancore: A0=P0, Ai=puntoMedio(Pi,Pi+1) per gli interni,
    // A(N-1)=P(N-1); ultimo segmento retto) - deve restare identica,
    // altrimenti il marcatore animato si scosta dalla curva disegnata.
    // Ogni segmento: {a, b, controllo: punto|null (null = retta)}.
    function costruisciSegmentiPercorso(puntiPx) {
        if (puntiPx.length < 2) return []
        if (puntiPx.length === 2) return [{a: puntiPx[0], b: puntiPx[1], controllo: null}]
        var segmenti = []
        var penna = puntiPx[0]
        for (var i = 1; i < puntiPx.length - 1; i++) {
            var fine = {x: (puntiPx[i].x + puntiPx[i + 1].x) / 2, y: (puntiPx[i].y + puntiPx[i + 1].y) / 2}
            segmenti.push({a: penna, b: fine, controllo: puntiPx[i]})
            penna = fine
        }
        segmenti.push({a: penna, b: puntiPx[puntiPx.length - 1], controllo: null})
        return segmenti
    }

    // Bezier quadratica (segmento curvo) o interpolazione lineare (retta),
    // in pixel, parametro locale u in [0,1].
    function valutaSegmentoPercorso(seg, u) {
        if (seg.controllo === null) {
            return {x: seg.a.x + (seg.b.x - seg.a.x) * u, y: seg.a.y + (seg.b.y - seg.a.y) * u}
        }
        var mu = 1 - u
        return {
            x: mu * mu * seg.a.x + 2 * mu * u * seg.controllo.x + u * u * seg.b.x,
            y: mu * mu * seg.a.y + 2 * mu * u * seg.controllo.y + u * u * seg.b.y,
        }
    }

    // Posizione normalizzata (0-1) di idElemento al tempo globale
    // tempoGlobale, se ha un percorso associato (ancoraId) visibile;
    // altrimenti null (il chiamante ricade sulla posizione statica).
    // Nessuna cache: ricalcolo O(N) ad ogni chiamata, trascurabile alla
    // scala di questa app (vedi piano - "Animazione", punto 5).
    function posizionePercorsoPer(idElemento, tempoGlobale) {
        var ancora = null
        for (var j = 0; j < coachingBoardVM.elementi.length; j++) {
            if (coachingBoardVM.elementi[j].id === idElemento) { ancora = coachingBoardVM.elementi[j]; break }
        }
        if (ancora) {
            var chiave = ancora.tipo === "pallone" ? "pallone" : ancora.squadra
            if (chiave && root.squadreVisibili[chiave] === false) return null
        }
        for (var i = 0; i < coachingBoardVM.elementi.length; i++) {
            var el = coachingBoardVM.elementi[i]
            if (el.tipo !== "percorso" || el.ancoraId !== idElemento) continue
            if (el.punti.length < 2) return null
            var segmenti = root.costruisciSegmentiPercorso(root.puntiPixelPercorso(el.punti))
            if (segmenti.length === 0) return null
            var lunghezze = []
            var lunghezzaTotale = 0
            for (var k = 0; k < segmenti.length; k++) {
                var s = segmenti[k]
                var l = Math.max(0.001, Math.hypot(s.b.x - s.a.x, s.b.y - s.a.y))
                lunghezze.push(l)
                lunghezzaTotale += l
            }
            var pathLocalT = Math.max(0, Math.min(el.durata, tempoGlobale - el.ritardo))
            var frazione = el.durata > 0 ? pathLocalT / el.durata : 1
            var lunghezzaTarget = frazione * lunghezzaTotale

            var accumulata = 0
            var puntoPixel = segmenti[segmenti.length - 1].b
            for (var m = 0; m < segmenti.length; m++) {
                if (m === segmenti.length - 1 || lunghezzaTarget <= accumulata + lunghezze[m]) {
                    var localU = lunghezze[m] > 0 ? Math.max(0, Math.min(1, (lunghezzaTarget - accumulata) / lunghezze[m])) : 0
                    puntoPixel = root.valutaSegmentoPercorso(segmenti[m], localU)
                    break
                }
                accumulata += lunghezze[m]
            }
            return {x: puntoPixel.x / campoTattico.width, y: puntoPixel.y / campoTattico.height}
        }
        return null
    }

    // Cattura un fotogramma alla volta (non tutti insieme): grabToImage e'
    // asincrono, il fotogramma successivo va pianificato solo DOPO che il
    // callback precedente e' tornato, altrimenti catture sovrapposte
    // scriverebbero risultati fuori ordine/incompleti.
    function catturaProssimoFotogramma() {
        if (root.fotogrammaEsportazione >= root.totaleFotogrammiEsportazione) {
            coachingBoardVM.esportaAnimazioneGif(root._fotogrammiCatturati, root.fpsEsportazione, root._destinazioneEsportazione)
            root.esportazioneInCorso = false
            root.inRiproduzione = false
            return
        }
        root.progressoAnimazione = Math.min(root.durataTotaleAnimazione, root.fotogrammaEsportazione / root.fpsEsportazione)
        var percorsoFotogramma = coachingBoardVM.percorsoFotogrammaTemporaneo(root.fotogrammaEsportazione)
        areaEsportabile.grabToImage(function(risultato) {
            risultato.saveToFile(percorsoFotogramma)
            root._fotogrammiCatturati = root._fotogrammiCatturati.concat([percorsoFotogramma])
            root.fotogrammaEsportazione += 1
            root.catturaProssimoFotogramma()
        })
    }

    Keys.onPressed: function(event) {
        if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.selezionati.length > 0) {
            dialogoConfermaEliminazione.apri(
                "Elimina elementi",
                "Rimuovere " + root.selezionati.length + " elemento/i selezionato/i dalla lavagna?",
                "Elimina",
                function() { coachingBoardVM.rimuoviElementi(root.selezionati); root.deselezionaTutto() }
            )
            event.accepted = true
        }
        if (event.key === Qt.Key_Escape && root.strumentoAttivo !== "") {
            root.strumentoAttivo = ""
            event.accepted = true
        }
        if (event.key === Qt.Key_Z && (event.modifiers & Qt.ControlModifier)) {
            coachingBoardVM.annulla()
            root.deselezionaTutto()
            event.accepted = true
        }
        if (event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier) && root.selezionati.length > 0) {
            coachingBoardVM.copiaElementi(root.selezionati)
            event.accepted = true
        }
        if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
            var nuovi = coachingBoardVM.incollaElementi()
            if (nuovi.length > 0) {
                root.selezionati = nuovi
                root.selezionato = nuovi[nuovi.length - 1]
            }
            event.accepted = true
        }
    }

    // Motore di riproduzione dell'animazione: un Timer che incrementa
    // progressoAnimazione, non una NumberAnimation - pausa/ripresa/scrub
    // diventano semplici assegnazioni di proprieta' (nessuna interpolazione
    // da fermare/ritargettare), e durataTotaleAnimazione puo' cambiare a
    // runtime mentre l'utente regola un ritardo (vedi piano, "Animazione").
    Timer {
        interval: 16
        running: root.inRiproduzione
        repeat: true
        onTriggered: {
            root.progressoAnimazione += interval / 1000
            if (root.progressoAnimazione >= root.durataTotaleAnimazione) {
                root.progressoAnimazione = root.durataTotaleAnimazione
                root.inRiproduzione = false
            }
        }
    }

    Column {
        id: colonnaPrincipale
        anchors.fill: parent
        anchors.margins: Theme.spacing.xl
        spacing: Theme.spacing.lg

        // ------------------------------------------------------------
        // Riga superiore: sidebar sinistra (impostazioni meno frequenti,
        // meta' lavagna, colori squadre, campo/scala, personalizza
        // selezionato) + campo. I pulsanti usati costantemente durante il
        // lavoro (aggiungi elementi, strumenti disegno) stanno invece nella
        // barra ORIZZONTALE sotto: prima erano tutti impilati nella sidebar
        // verticale e serviva scorrere per vederli tutti - lo spazio sotto
        // il campo, prima inutilizzato, li rende visibili senza scroll.
        // ------------------------------------------------------------
        Row {
            id: rigaSuperiore
            width: parent.width
            // Il Column esterno impila solo rigaSuperiore + separatoreInferiore
            // + barraInferiore: la card "Animazione" (piu' sotto) e' un Popup
            // flottante fuori da questo Column, non consuma spazio qui
            // (segnalato da Luca: la versione a riga fissa "occupa tanto
            // spazio e limita lo spazio di lavoro").
            height: parent.height - barraInferiore.height - separatoreInferiore.height - Theme.spacing.lg * 2
            spacing: Theme.spacing.lg

        Flickable {
            id: barraLaterale
            // Ridotta da 300 a 230 di default: il campo (scalaCampo, sopra)
            // riempie per costruzione lo spazio che avanza da questa sidebar
            // e dalla barra inferiore, senza alcun clamp massimo - restringere
            // la sidebar fissa e' quindi il modo piu' diretto e sicuro
            // (tocca solo geometria) per far crescere il campo (segnalato
            // da Luca: "il campo occupa una porzione troppo piccola").
            // Larghezza ora regolabile a mano tramite lo splitter subito
            // sotto (drag tra 230 e 460px) per chi trova i controlli troppo
            // stretti - vedi root.larghezzaSidebar.
            width: root.larghezzaSidebar
            height: parent.height
            contentWidth: width
            contentHeight: colonnaSidebar.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Column {
                id: colonnaSidebar
                width: parent.width
                spacing: Theme.spacing.lg

                FMCard {
                    width: parent.width
                    title: "Lavagna tattica"

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.sm

                        TextField {
                            width: parent.width
                            placeholderText: "Titolo"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: coachingBoardVM.titolo
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            // BUG (segnalato da Luca): "Salva" e' un Button
                            // Qt Quick Controls, che di default NON ruba il
                            // focus al click (focusPolicy TabFocus, non
                            // ClickFocus) - digitare il nuovo titolo e
                            // cliccare subito "Salva" lasciava il focus
                            // sempre su questo campo, quindi onEditingFinished
                            // non scattava mai e veniva salvato ancora il
                            // vecchio titolo. onTextChanged aggiorna il VM ad
                            // ogni carattere, senza dipendere dal focus.
                            onTextChanged: coachingBoardVM.impostaTitolo(text)
                        }
                        FMComboBox {
                            id: comboMezzo
                            width: parent.width
                            editable: true
                            model: coachingBoardVM.listaMezzi
                            onEditTextChanged: coachingBoardVM.impostaMezzoAllenamento(editText)
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            Component.onCompleted: editText = coachingBoardVM.mezzoAllenamento
                        }
                        TextField {
                            width: parent.width
                            placeholderText: "Note / descrizione della lavagna"
                            placeholderTextColor: Theme.colors.textSecondary
                            text: coachingBoardVM.descrizione
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                            background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                            onEditingFinished: coachingBoardVM.impostaDescrizione(text)
                        }
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            FMButton { text: "Nuova"; onClicked: { coachingBoardVM.nuovaLavagna(); root.deselezionaTutto(); root.strumentoAttivo = "" } }
                            FMButton { text: "Torna all'archivio"; onClicked: navigazioneVM.vaiA(6) }
                            FMButton {
                                primary: true
                                text: "Salva"
                                onClicked: {
                                    var percorso = coachingBoardVM.percorsoImmaginePerSalvataggio()
                                    areaEsportabile.grabToImage(function(risultato) {
                                        risultato.saveToFile(percorso)
                                        coachingBoardVM.confermaSalvataggio(percorso)
                                    })
                                }
                            }
                            // Unico interruttore che rivela la riga "Animazione"
                            // (barraAnimazione, piu' sotto) - senza questo
                            // pulsante la card resta permanentemente nascosta
                            // (visible: root.modalitaAnimazione, mai altrimenti
                            // impostato a true da nessun altro controllo).
                            FMButton {
                                primary: root.modalitaAnimazione
                                text: root.modalitaAnimazione ? "Esci da Modalità Animazione" : "Modalità Animazione"
                                onClicked: {
                                    root.modalitaAnimazione = !root.modalitaAnimazione
                                    root.inRiproduzione = false
                                    if (!root.modalitaAnimazione) root.strumentoAttivo = ""
                                }
                            }
                        }
                        Text {
                            visible: coachingBoardVM.messaggio !== ""
                            text: coachingBoardVM.messaggio
                            color: Theme.colors.positive
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.small
                        }
                    }
                }

                FMCard {
                    width: parent.width
                    title: "Colori squadre"

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.xs
                        Text { text: "Tutti i giocatori gia' piazzati vengono ricolorati insieme"; wrapMode: Text.WordWrap; width: parent.width; color: Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                        Text { text: "Squadra 1 - Maglia"; color: Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                        FMSelettoreColore {
                            coloreAttuale: root.coloreMagliaSquadraA
                            onColorScelto: function(c) { root.coloreMagliaSquadraA = c; coachingBoardVM.impostaColoreMagliaSquadra("a", c); coachingBoardVM.scriviImpostazione("coloreMagliaSquadraA", c) }
                        }
                        Text { text: "Squadra 1 - Calzettoni"; color: Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                        FMSelettoreColore {
                            coloreAttuale: root.coloreCalzeSquadraA
                            onColorScelto: function(c) { root.coloreCalzeSquadraA = c; coachingBoardVM.impostaColoreCalzeSquadra("a", c); coachingBoardVM.scriviImpostazione("coloreCalzeSquadraA", c) }
                        }
                        Text { text: "Squadra 2 - Maglia"; color: Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                        FMSelettoreColore {
                            coloreAttuale: root.coloreMagliaSquadraB
                            onColorScelto: function(c) { root.coloreMagliaSquadraB = c; coachingBoardVM.impostaColoreMagliaSquadra("b", c); coachingBoardVM.scriviImpostazione("coloreMagliaSquadraB", c) }
                        }
                        Text { text: "Squadra 2 - Calzettoni"; color: Theme.colors.textTertiary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption }
                        FMSelettoreColore {
                            coloreAttuale: root.coloreCalzeSquadraB
                            onColorScelto: function(c) { root.coloreCalzeSquadraB = c; coachingBoardVM.impostaColoreCalzeSquadra("b", c); coachingBoardVM.scriviImpostazione("coloreCalzeSquadraB", c) }
                        }
                    }
                }

                FMCard {
                    width: parent.width
                    title: "Campo e scala"

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.sm

                        Text { text: "Modalita' campo"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            Repeater {
                                model: [ {v: "intero", l: "Campo intero"}, {v: "meta", l: "Meta' campo"}, {v: "nessuna", l: "Nessuna linea"} ]
                                delegate: FMButton {
                                    text: modelData.l
                                    primary: coachingBoardVM.modalitaCampo === modelData.v
                                    onClicked: coachingBoardVM.impostaModalitaCampo(modelData.v)
                                }
                            }
                        }

                        // Semplificato rispetto a prima: due soli pulsanti che
                        // aprono un selettore colore al volo, non l'intera
                        // tavolozza sempre visibile in pagina ("non serve
                        // avere tutte le colorazioni del campo disponibili
                        // la'" - fix consegnato).
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            FMButton { text: "🎨 Sfondo"; onClicked: popupColoreSfondo.open() }
                            FMButton { text: "🎨 Linee"; onClicked: popupColoreLinee.open() }
                        }

                        Text { text: "Scala giocatori (" + Math.round(coachingBoardVM.scalaGiocatori * 100) + "%)"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Slider { width: parent.width; from: 0.5; to: 2.0; value: coachingBoardVM.scalaGiocatori; onMoved: coachingBoardVM.impostaScalaGiocatori(value) }
                        Text { text: "Scala oggetti (" + Math.round(coachingBoardVM.scalaOggetti * 100) + "%)"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Slider { width: parent.width; from: 0.5; to: 2.0; value: coachingBoardVM.scalaOggetti; onMoved: coachingBoardVM.impostaScalaOggetti(value) }
                    }
                }

                FMCard {
                    width: parent.width
                    title: "Giocatori"

                    Row {
                        spacing: Theme.spacing.xs
                        CheckBox {
                            checked: coachingBoardVM.mostraEtichetteGlobali
                            onToggled: coachingBoardVM.impostaMostraEtichetteGlobali(checked)
                        }
                        Text { text: "Mostra Nomi e Numeri visibili"; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.small; anchors.verticalCenter: parent.verticalCenter }
                    }
                }

                FMCard {
                    width: parent.width
                    visible: root.elementoSelezionato() !== null
                    title: "Personalizza elemento selezionato"

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.sm
                        visible: root.elementoSelezionato() !== null && !root.eForma(root.elementoSelezionato().tipo) && root.elementoSelezionato().tipo !== "testo"

                        Text { text: "Dimensione (" + Math.round((root.elementoSelezionato() ? root.elementoSelezionato().scalaIndividuale : 1.0) * 100) + "%)"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Slider {
                            width: parent.width
                            from: 0.3; to: 3.0
                            value: root.elementoSelezionato() ? root.elementoSelezionato().scalaIndividuale : 1.0
                            onMoved: coachingBoardVM.impostaScalaIndividualeElemento(root.selezionato, value)
                        }

                        Text { text: "Rotazione"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            Repeater {
                                model: [0, 45, 90, 135, 180, 225, 270, 315]
                                delegate: FMButton {
                                    text: modelData + "°"
                                    primary: root.elementoSelezionato() && root.elementoSelezionato().rotazione === modelData
                                    onClicked: coachingBoardVM.impostaRotazioneElemento(root.selezionato, modelData)
                                }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.sm
                        visible: root.elementoSelezionato() !== null && (root.elementoSelezionato().tipo === "giocatore" || root.elementoSelezionato().tipo === "pallone" || root.elementoSelezionato().tipo === "cerchio" || root.elementoSelezionato().tipo === "palo" || root.elementoSelezionato().tipo === "conetto")

                        Text { text: root.elementoSelezionato() && root.elementoSelezionato().tipo === "giocatore" ? "Maglia" : "Colore"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        FMSelettoreColore {
                            coloreAttuale: root.elementoSelezionato() ? root.elementoSelezionato().colore : ""
                            onColorScelto: function(c) { coachingBoardVM.impostaColoreElemento(root.selezionato, c) }
                        }
                        Text {
                            visible: root.elementoSelezionato() !== null && root.elementoSelezionato().tipo !== "conetto"
                            text: root.elementoSelezionato() && root.elementoSelezionato().tipo === "giocatore" ? "Pantaloncini" : "Contorno"
                            color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true
                        }
                        FMSelettoreColore {
                            visible: root.elementoSelezionato() !== null && root.elementoSelezionato().tipo !== "conetto"
                            coloreAttuale: root.elementoSelezionato() ? root.elementoSelezionato().coloreContorno : ""
                            onColorScelto: function(c) { coachingBoardVM.impostaColoreContornoElemento(root.selezionato, c) }
                        }
                        Column {
                            visible: root.elementoSelezionato() !== null && root.elementoSelezionato().tipo === "giocatore"
                            spacing: Theme.spacing.xs
                            Text { text: "Numero / Nome"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                            Row {
                                spacing: Theme.spacing.xs
                                TextField {
                                    width: 50
                                    text: root.elementoSelezionato() ? root.elementoSelezionato().numero : ""
                                    color: Theme.colors.textPrimary
                                    font.family: Theme.typography.family
                                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                    onEditingFinished: coachingBoardVM.impostaNumeroGiocatore(root.selezionato, text)
                                }
                                TextField {
                                    width: 140
                                    placeholderText: "Nome giocatore"
                                    placeholderTextColor: Theme.colors.textSecondary
                                    text: root.elementoSelezionato() ? root.elementoSelezionato().nomeGiocatore : ""
                                    color: Theme.colors.textPrimary
                                    font.family: Theme.typography.family
                                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                                    onEditingFinished: coachingBoardVM.impostaNomeGiocatore(root.selezionato, text)
                                }
                            }
                            Row {
                                spacing: Theme.spacing.xs
                                CheckBox {
                                    checked: root.elementoSelezionato() ? root.elementoSelezionato().mostraEtichetta : true
                                    onToggled: coachingBoardVM.impostaMostraEtichetta(root.selezionato, checked)
                                }
                                Text { text: "Mostra numero/nome"; color: Theme.colors.textPrimary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.small; anchors.verticalCenter: parent.verticalCenter }
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.sm
                        visible: root.elementoSelezionato() !== null && root.elementoSelezionato().tipo === "porta"

                        Text { text: "Dimensione"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Row {
                            spacing: Theme.spacing.xs
                            FMButton { text: "Grande"; primary: root.elementoSelezionato() && root.elementoSelezionato().dimensione === "grande"; onClicked: coachingBoardVM.impostaDimensionePorta(root.selezionato, "grande") }
                            FMButton { text: "Piccola"; primary: root.elementoSelezionato() && root.elementoSelezionato().dimensione === "piccola"; onClicked: coachingBoardVM.impostaDimensionePorta(root.selezionato, "piccola") }
                        }
                    }

                    Row {
                        width: parent.width
                        visible: root.elementoSelezionato() !== null && root.elementoSelezionato().tipo === "testo"
                        FMButton {
                            text: "Modifica testo…"
                            onClicked: {
                                var el = root.elementoSelezionato()
                                dialogoTesto.apriPer(root.selezionato, el.testo, el.fontSize, el.grassetto, el.coloreTesto)
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.sm
                        visible: root.elementoSelezionato() !== null && root.eForma(root.elementoSelezionato().tipo)

                        Text { text: "Colore forma"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        FMSelettoreColore {
                            coloreAttuale: root.elementoSelezionato() ? root.elementoSelezionato().colore : ""
                            onColorScelto: function(c) { coachingBoardVM.impostaColoreElemento(root.selezionato, c) }
                        }
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            FMButton { text: "Continuo"; primary: root.elementoSelezionato() && !root.elementoSelezionato().tratteggiato; onClicked: coachingBoardVM.impostaTratteggiatoForma(root.selezionato, false) }
                            FMButton { text: "Tratteggiato"; primary: root.elementoSelezionato() && root.elementoSelezionato().tratteggiato; onClicked: coachingBoardVM.impostaTratteggiatoForma(root.selezionato, true) }
                        }
                        Text { text: "Spessore (" + (root.elementoSelezionato() ? root.elementoSelezionato().spessore.toFixed(0) : "2") + "px)"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Slider {
                            width: parent.width
                            from: 1; to: 8; stepSize: 1
                            value: root.elementoSelezionato() ? root.elementoSelezionato().spessore : 2
                            onMoved: coachingBoardVM.impostaSpessoreForma(root.selezionato, value)
                        }
                    }
                }
            }
        }

        // ------------------------------------------------------------
        // Splitter draggabile tra sidebar e campo: sposta solo
        // root.larghezzaSidebar (clamp min/max sopra), mai l'altezza.
        // mouse.x va rimappato su rigaSuperiore (che non si muove) invece
        // di restare relativo a questo Item, che invece si riposiziona
        // ogni frame appena la sidebar cambia larghezza - usare mouse.x
        // locale come delta produrrebbe un drag instabile/a scatti.
        // ------------------------------------------------------------
        Item {
            id: separatoreSidebar
            width: 8
            height: parent.height
            property real xPressStart: 0
            property real larghezzaPressStart: 0

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 2
                height: parent.height
                radius: 1
                color: Theme.colors.border
                opacity: areaSplitter.containsMouse || areaSplitter.pressed ? 0.9 : 0.35
            }

            MouseArea {
                id: areaSplitter
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeHorCursor
                onPressed: function(mouse) {
                    var p = areaSplitter.mapToItem(rigaSuperiore, mouse.x, mouse.y)
                    separatoreSidebar.xPressStart = p.x
                    separatoreSidebar.larghezzaPressStart = root.larghezzaSidebar
                }
                onPositionChanged: function(mouse) {
                    if (!areaSplitter.pressed) return
                    var p = areaSplitter.mapToItem(rigaSuperiore, mouse.x, mouse.y)
                    var delta = p.x - separatoreSidebar.xPressStart
                    root.larghezzaSidebar = Math.max(root.larghezzaSidebarMinima, Math.min(root.larghezzaSidebarMassima, separatoreSidebar.larghezzaPressStart + delta))
                }
            }
        }

        // ------------------------------------------------------------
        // Area campo, a destra della sidebar.
        // ------------------------------------------------------------
        Flickable {
            id: flickableCampo
            width: parent.width - barraLaterale.width - separatoreSidebar.width - Theme.spacing.lg * 2
            height: parent.height
            contentWidth: Math.max(width, areaEsportabile.width)
            contentHeight: Math.max(height, areaEsportabile.height)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

            // Contenitore piu' ampio del campo vero e proprio: i segni di
            // porta sporgono oltre il rettangolo campoTattico (sono ancorati
            // alla linea di fondo ma disegnati un po' fuori, verso l'esterno)
            // e grabToImage() cattura ESATTAMENTE le dimensioni dell'item su
            // cui viene chiamato - prima si chiamava su campoTattico stesso,
            // quindi le porte restavano tagliate fuori dall'immagine
            // salvata. Il margine da tutti i lati e' generoso quanto la
            // profondita' del segno porta, cosi' campo+porte ci stanno
            // sempre per intero qualunque sia la modalita' (intero: sporgono
            // a sinistra/destra; meta': sporge in alto).
            Item {
                id: areaEsportabile
                objectName: "areaEsportabile"
                width: campoTattico.width + 2 * root.margineEsportazione
                height: campoTattico.height + 2 * root.margineEsportazione
                x: Math.max(0, (parent.width - width) / 2)
                y: Math.max(0, (parent.height - height) / 2)

                // Sfondo verde esteso a tutta l'area esportabile (campo +
                // margine porte), non solo al rettangolo campoTattico: senza
                // questo, il margine attorno al campo restava trasparente e
                // le porte sporgenti apparivano "staccate" dal verde invece
                // che contenute dentro un unico rettangolo verde piu' ampio.
                Rectangle {
                    anchors.fill: parent
                    color: coachingBoardVM.coloreCampo
                    radius: Theme.radius.md
                }

                Rectangle {
                    id: campoTattico
                    // In modalita' "meta" il campo mostrato e' davvero solo meta'
                    // campo (non l'intero campo con l'altra meta' semplicemente
                    // nascosta), E in verticale con la porta in alto (non piu'
                    // in orizzontale con la porta a sinistra): gli assi si
                    // scambiano rispetto a "intero" - l'asse larghezza-campo
                    // reale (altezzaCampo) diventa la larghezza visualizzata,
                    // meta' dell'asse lunghezza-campo (larghezzaCampo/2) diventa
                    // l'altezza. Le coordinate normalizzate x*width/y*height
                    // degli elementi si riadattano da sole al nuovo rettangolo.
                    readonly property bool meta: coachingBoardVM.modalitaCampo === "meta"
                    width: root.campoDimensioneMeta ? root.altezzaCampo : root.larghezzaCampo
                    height: root.campoDimensioneMeta ? root.larghezzaCampo / 2 : root.altezzaCampo
                    x: root.margineEsportazione
                    y: root.margineEsportazione
                    color: coachingBoardVM.coloreCampo
                    radius: Theme.radius.md
                    border.width: 4
                    border.color: coachingBoardVM.coloreLinee

                // Erba a strisce: bande verticali alternate leggermente piu'
                // scure sopra al colore campo piatto, parallele alla linea
                // di meta' campo (stesso effetto "tosata a strisce" dei
                // campi veri) - puramente decorativo, non tocca in alcun
                // modo il sistema di coordinate normalizzate sotto. Niente
                // clip sul Rectangle campoTattico stesso (elementi/forme
                // trascinati vicino al bordo devono poter sporgere come
                // prima): il Canvas ritaglia da solo un rettangolo
                // arrotondato pari al raggio del campo, cosi' le strisce non
                // sporgono dagli angoli smussati.
                Canvas {
                    id: telaErba
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        var r = Theme.radius.md
                        ctx.beginPath()
                        ctx.moveTo(r, 0)
                        ctx.arcTo(width, 0, width, height, r)
                        ctx.arcTo(width, height, 0, height, r)
                        ctx.arcTo(0, height, 0, 0, r)
                        ctx.arcTo(0, 0, width, 0, r)
                        ctx.closePath()
                        ctx.clip()

                        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.06)
                        if (root.campoDimensioneMeta) {
                            // Bande orizzontali: restano parallele alla linea
                            // di meta' campo, che qui e' orizzontale (in
                            // basso), non piu' verticale.
                            var passoY = Math.max(24, height / 14)
                            for (var y = 0, bandaY = 0; y < height; y += passoY, bandaY++) {
                                if (bandaY % 2 === 0) ctx.fillRect(0, y, width, passoY)
                            }
                        } else {
                            var passoX = Math.max(24, width / 14)
                            for (var x = 0, bandaX = 0; x < width; x += passoX, bandaX++) {
                                if (bandaX % 2 === 0) ctx.fillRect(x, 0, passoX, height)
                            }
                        }
                    }
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                }

                // Linea di meta' campo: verticale, perche' le porte sono sui
                // lati corti (sinistra/destra) di un campo piu' largo che
                // alto - prima erano (erroneamente) sui lati lunghi
                // (sopra/sotto), fix segnalato esplicitamente.
                Rectangle {
                    visible: coachingBoardVM.modalitaCampo === "intero"
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    width: 2
                    height: parent.height
                    color: coachingBoardVM.coloreLinee
                    opacity: 0.8
                }
                // Cerchio di centrocampo: intero in modalita' "intero"; in
                // "meta" diventa un semicerchio tagliato sul bordo dove passa
                // la linea di meta' campo - che ora e' il bordo INFERIORE
                // (porta in alto, non piu' il bordo destro).
                Item {
                    visible: coachingBoardVM.modalitaCampo !== "nessuna"
                    anchors.fill: parent
                    clip: campoTattico.meta
                    Rectangle {
                        readonly property real r: root.cerchioCentrocampoRaggio
                        x: parent.width / 2 - r
                        y: (campoTattico.meta ? parent.height : parent.height / 2) - r
                        width: r * 2; height: r * 2
                        radius: r
                        color: "transparent"
                        border.width: 2
                        border.color: coachingBoardVM.coloreLinee
                        opacity: 0.8
                    }
                }

                // Area di rigore + area piccola + segno porta, lato
                // sinistro in modalita' "intero" (porta a sinistra), lato
                // superiore in modalita' "meta" (porta in alto) - stesso
                // Rectangle, geometria che si scambia in base alla modalita'
                // invece di duplicare i blocchi.
                Rectangle {
                    visible: coachingBoardVM.modalitaCampo !== "nessuna"
                    x: campoTattico.meta ? (campoTattico.width - root.boxSpan) / 2 : 0
                    y: campoTattico.meta ? 0 : (campoTattico.height - root.boxSpan) / 2
                    width: campoTattico.meta ? root.boxSpan : root.boxProfondita
                    height: campoTattico.meta ? root.boxProfondita : root.boxSpan
                    color: "transparent"; border.width: 2; border.color: coachingBoardVM.coloreLinee; opacity: 0.8
                }
                Rectangle {
                    visible: coachingBoardVM.modalitaCampo !== "nessuna"
                    x: campoTattico.meta ? (campoTattico.width - root.areaPiccolaSpan) / 2 : 0
                    y: campoTattico.meta ? 0 : (campoTattico.height - root.areaPiccolaSpan) / 2
                    width: campoTattico.meta ? root.areaPiccolaSpan : root.areaPiccolaProfondita
                    height: campoTattico.meta ? root.areaPiccolaProfondita : root.areaPiccolaSpan
                    color: "transparent"; border.width: 2; border.color: coachingBoardVM.coloreLinee; opacity: 0.8
                }
                FMPortaCampo {
                    // Stessa grafica (rete + pali) della porta piazzabile
                    // FMPortaCampo, cosi' il segno porta incluso nel campo e
                    // l'oggetto "+ Porta" che si trascina liberamente sono
                    // visivamente identici invece di due grafiche diverse.
                    visible: coachingBoardVM.modalitaCampo !== "nessuna"
                    x: campoTattico.meta ? (campoTattico.width - root.segnoPortaSpan) / 2 : -root.segnoPortaProfondita
                    y: campoTattico.meta ? -root.segnoPortaProfondita : (campoTattico.height - root.segnoPortaSpan) / 2
                    width: campoTattico.meta ? root.segnoPortaSpan : root.segnoPortaProfondita
                    height: campoTattico.meta ? root.segnoPortaProfondita : root.segnoPortaSpan
                    colore: coachingBoardVM.coloreLinee
                    opacity: 0.8
                }
                Item {
                    visible: coachingBoardVM.modalitaCampo === "intero"
                    x: root.boxProfondita; y: (root.altezzaCampo - 120 * root.scalaCampo) / 2
                    width: 30 * root.scalaCampo; height: 120 * root.scalaCampo
                    clip: true
                    Rectangle {
                        x: -98 * root.scalaCampo; y: -1
                        width: 122 * root.scalaCampo; height: 122 * root.scalaCampo; radius: root.arcoAngoloRaggio
                        color: "transparent"; border.width: 2; border.color: coachingBoardVM.coloreLinee; opacity: 0.8
                    }
                }

                // Area di rigore + area piccola + porta, lato destro
                // (speculare). Solo in modalita' "intero": in "meta" il lato
                // destro resta sempre nascosto, dato che li' non c'e' piu'
                // campo (il rettangolo campoTattico e' dimezzato).
                Rectangle {
                    visible: coachingBoardVM.modalitaCampo === "intero"
                    x: root.larghezzaCampo - root.boxProfondita; y: (root.altezzaCampo - root.boxSpan) / 2
                    width: root.boxProfondita; height: root.boxSpan
                    color: "transparent"; border.width: 2; border.color: coachingBoardVM.coloreLinee; opacity: 0.8
                }
                Rectangle {
                    visible: coachingBoardVM.modalitaCampo === "intero"
                    x: root.larghezzaCampo - root.areaPiccolaProfondita; y: (root.altezzaCampo - root.areaPiccolaSpan) / 2
                    width: root.areaPiccolaProfondita; height: root.areaPiccolaSpan
                    color: "transparent"; border.width: 2; border.color: coachingBoardVM.coloreLinee; opacity: 0.8
                }
                FMPortaCampo {
                    visible: coachingBoardVM.modalitaCampo === "intero"
                    x: root.larghezzaCampo; y: (root.altezzaCampo - root.segnoPortaSpan) / 2
                    width: root.segnoPortaProfondita; height: root.segnoPortaSpan
                    colore: coachingBoardVM.coloreLinee
                    opacity: 0.8
                }
                Item {
                    visible: coachingBoardVM.modalitaCampo === "intero"
                    x: root.larghezzaCampo - 140 * root.scalaCampo; y: (root.altezzaCampo - 120 * root.scalaCampo) / 2
                    width: 30 * root.scalaCampo; height: 120 * root.scalaCampo
                    clip: true
                    Rectangle {
                        x: 6 * root.scalaCampo; y: -1
                        width: 122 * root.scalaCampo; height: 122 * root.scalaCampo; radius: root.arcoAngoloRaggio
                        color: "transparent"; border.width: 2; border.color: coachingBoardVM.coloreLinee; opacity: 0.8
                    }
                }

                MouseArea {
                    // Area vuota del campo: click normale = deseleziona;
                    // con uno strumento di disegno attivo, premi-trascina-
                    // rilascia crea una nuova forma tra i due punti; senza
                    // strumento attivo, premi-trascina-rilascia seleziona
                    // tutti gli elementi dentro il rettangolo tracciato
                    // (selezione multipla "a lazo", non solo Ctrl+click).
                    anchors.fill: parent
                    onPressed: function(mouse) {
                        // Animazione: con lo strumento "percorso" armato, un
                        // press su campo VUOTO (non su un giocatore/pallone,
                        // gia' gestito dalla MouseArea del delegate sopra)
                        // non deve fare nulla - il gesto parte SOLO da un
                        // marcatore, mai da qui.
                        if (root.strumentoAttivo !== "" && root.strumentoAttivo !== "percorso") {
                            root.disegnoInizio = Qt.point(mouse.x, mouse.y)
                            root.disegnoFine = Qt.point(mouse.x, mouse.y)
                            root.disegnandoForma = true
                        } else if (root.strumentoAttivo === "") {
                            root.selezioneInizio = Qt.point(mouse.x, mouse.y)
                            root.selezioneFine = Qt.point(mouse.x, mouse.y)
                            root.selezionandoRettangolo = true
                        }
                    }
                    onPositionChanged: function(mouse) {
                        if (root.disegnandoForma) root.disegnoFine = Qt.point(mouse.x, mouse.y)
                        else if (root.selezionandoRettangolo) root.selezioneFine = Qt.point(mouse.x, mouse.y)
                    }
                    onReleased: function(mouse) {
                        if (root.disegnandoForma) {
                            root.disegnandoForma = false
                            var dx = mouse.x - root.disegnoInizio.x
                            var dy = mouse.y - root.disegnoInizio.y
                            if (Math.abs(dx) > 4 || Math.abs(dy) > 4) {
                                coachingBoardVM.aggiungiForma(
                                    root.strumentoAttivo,
                                    root.disegnoInizio.x / campoTattico.width, root.disegnoInizio.y / campoTattico.height,
                                    mouse.x / campoTattico.width, mouse.y / campoTattico.height,
                                    root.coloreDisegnoAttivo, root.tratteggiatoAttivo, root.spessoreDisegnoAttivo
                                )
                            }
                        } else if (root.selezionandoRettangolo) {
                            root.selezionandoRettangolo = false
                            var sdx = mouse.x - root.selezioneInizio.x
                            var sdy = mouse.y - root.selezioneInizio.y
                            if (Math.abs(sdx) > 4 || Math.abs(sdy) > 4) {
                                var sinistra = Math.min(root.selezioneInizio.x, mouse.x)
                                var destra = Math.max(root.selezioneInizio.x, mouse.x)
                                var sopra = Math.min(root.selezioneInizio.y, mouse.y)
                                var sotto = Math.max(root.selezioneInizio.y, mouse.y)
                                var trovati = []
                                for (var i = 0; i < coachingBoardVM.elementi.length; i++) {
                                    var el = coachingBoardVM.elementi[i]
                                    var px = el.x * campoTattico.width
                                    var py = el.y * campoTattico.height
                                    if (px >= sinistra && px <= destra && py >= sopra && py <= sotto) trovati.push(i)
                                }
                                root.selezionati = trovati
                                root.selezionato = trovati.length > 0 ? trovati[trovati.length - 1] : -1
                            } else {
                                root.deselezionaTutto()
                            }
                        }
                    }
                }

                // Anteprima dal vivo mentre si disegna una nuova forma.
                FMFormaLavagna {
                    visible: root.disegnandoForma
                    p1: root.disegnoInizio
                    p2: root.disegnoFine
                    tipo: root.strumentoAttivo === "" ? "linea" : root.strumentoAttivo
                    colore: root.coloreDisegnoAttivo
                    tratteggiato: root.tratteggiatoAttivo
                    interattivo: false
                }

                // Anteprima dal vivo mentre si disegna un percorso di
                // movimento (Animazione) - stesso principio del ghost sopra.
                FMPercorsoLavagna {
                    visible: root.disegnandoPercorso
                    punti: root.percorsoPuntiAnteprima
                    colore: root.coloreDisegnoAttivo
                    tratteggiato: root.tratteggiatoAttivo
                    spessore: root.spessoreDisegnoAttivo
                    interattivo: false
                }

                // Anteprima dal vivo del rettangolo di selezione multipla.
                Rectangle {
                    visible: root.selezionandoRettangolo
                    x: Math.min(root.selezioneInizio.x, root.selezioneFine.x)
                    y: Math.min(root.selezioneInizio.y, root.selezioneFine.y)
                    width: Math.abs(root.selezioneFine.x - root.selezioneInizio.x)
                    height: Math.abs(root.selezioneFine.y - root.selezioneInizio.y)
                    color: Theme.colors.accentSoft
                    border.width: 1
                    border.color: Theme.colors.accent
                }

                Repeater {
                    model: coachingBoardVM.elementi
                    delegate: Item {
                        id: elemento
                        visible: !root.eForma(modelData.tipo)
                        property var datiElemento: modelData
                        property int indiceElemento: index
                        readonly property bool selezionatoQui: root.isSelezionato(indiceElemento)
                        readonly property real scala: ((datiElemento.tipo === "giocatore") ? coachingBoardVM.scalaGiocatori : coachingBoardVM.scalaOggetti) * datiElemento.scalaIndividuale

                        readonly property real offsetGruppoX: (root.trascinandoMultiplo && elemento.selezionatoQui) ? root.trascinamentoDx : 0
                        readonly property real offsetGruppoY: (root.trascinandoMultiplo && elemento.selezionatoQui) ? root.trascinamentoDy : 0
                        // Animazione: quando modalitaAnimazione e' false il
                        // ternario sotto restituisce {x:datiElemento.x,
                        // y:datiElemento.y} - IDENTICO in valore a prima di
                        // questa property - quindi il binding x/y sotto
                        // resta bit-per-bit invariato per chi non usa mai la
                        // funzione (vedi piano, sezione "Animazione").
                        readonly property var posizioneEffettiva: (root.modalitaAnimazione && (datiElemento.tipo === "giocatore" || datiElemento.tipo === "pallone"))
                            ? (root.posizionePercorsoPer(datiElemento.id, root.progressoAnimazione) || {x: datiElemento.x, y: datiElemento.y})
                            : {x: datiElemento.x, y: datiElemento.y}
                        x: posizioneEffettiva.x * campoTattico.width - width / 2 + offsetGruppoX
                        y: posizioneEffettiva.y * campoTattico.height - height / 2 + offsetGruppoY
                        z: indiceElemento
                        rotation: datiElemento.rotazione

                        width: {
                            if (datiElemento.tipo === "porta") return (datiElemento.dimensione === "piccola" ? 60 : 90) * scala
                            if (datiElemento.tipo === "testo") return testoVisibile.implicitWidth + Theme.spacing.md
                            if (datiElemento.tipo === "cono") return 22 * scala
                            if (datiElemento.tipo === "conetto") return 18 * scala
                            if (datiElemento.tipo === "palo") return 7 * scala
                            if (datiElemento.tipo === "scaletta") return 54 * scala
                            if (datiElemento.tipo === "cerchio") return 32 * scala
                            if (datiElemento.tipo === "giocatore") return 44.8 * scala
                            if (datiElemento.tipo === "pallone") return 11.2 * scala
                            return 28 * scala
                        }
                        height: {
                            if (datiElemento.tipo === "porta") return (datiElemento.dimensione === "piccola" ? 16 : 22) * scala
                            if (datiElemento.tipo === "testo") return testoVisibile.implicitHeight + Theme.spacing.sm
                            if (datiElemento.tipo === "cono") return 28 * scala
                            if (datiElemento.tipo === "conetto") return 18 * scala
                            if (datiElemento.tipo === "palo") return 42 * scala
                            if (datiElemento.tipo === "scaletta") return 20 * scala
                            if (datiElemento.tipo === "cerchio") return 32 * scala
                            if (datiElemento.tipo === "giocatore") return 44.8 * scala
                            if (datiElemento.tipo === "pallone") return 11.2 * scala
                            return 28 * scala
                        }

                        FMGiocatoreForma {
                            id: sagomaGiocatore
                            visible: elemento.datiElemento.tipo === "giocatore"
                            anchors.fill: parent
                            colore: elemento.datiElemento.colore
                            coloreContorno: elemento.selezionatoQui ? Theme.colors.accent : elemento.datiElemento.coloreContorno
                            selezionato: elemento.selezionatoQui
                        }
                        FMPallone {
                            visible: elemento.datiElemento.tipo === "pallone"
                            anchors.fill: parent
                        }
                        Image {
                            visible: elemento.datiElemento.tipo === "cono"
                            anchors.fill: parent
                            source: Qt.resolvedUrl("../../assets/board/cono.png")
                            fillMode: Image.PreserveAspectFit
                        }
                        FMConettoForma {
                            visible: elemento.datiElemento.tipo === "conetto"
                            anchors.fill: parent
                            colore: elemento.datiElemento.colore
                        }
                        Rectangle {
                            visible: elemento.datiElemento.tipo === "palo"
                            anchors.fill: parent
                            radius: width / 2
                            color: elemento.datiElemento.colore
                            border.width: elemento.selezionatoQui ? 2 : 1
                            border.color: elemento.selezionatoQui ? Theme.colors.accent : elemento.datiElemento.coloreContorno
                        }
                        Item {
                            visible: elemento.datiElemento.tipo === "scaletta"
                            anchors.fill: parent
                            Rectangle { y: 0; width: parent.width; height: 2; color: elemento.datiElemento.colore }
                            Rectangle { y: parent.height - 2; width: parent.width; height: 2; color: elemento.datiElemento.colore }
                            Row {
                                anchors.fill: parent
                                Repeater {
                                    model: 5
                                    delegate: Item {
                                        width: parent.width / 5; height: parent.height
                                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; width: 2; height: parent.height; color: elemento.datiElemento.colore }
                                    }
                                }
                            }
                            Rectangle {
                                visible: elemento.selezionatoQui
                                anchors.fill: parent
                                color: "transparent"; border.width: 1; border.color: Theme.colors.accent; opacity: 0.7
                            }
                        }
                        Rectangle {
                            visible: elemento.datiElemento.tipo === "cerchio"
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.width: elemento.selezionatoQui ? 3 : 2
                            border.color: elemento.selezionatoQui ? Theme.colors.accent : elemento.datiElemento.colore
                        }

                        Rectangle {
                            visible: ["giocatore", "pallone", "cono", "conetto", "palo", "scaletta", "cerchio", "porta"].indexOf(elemento.datiElemento.tipo) === -1 && elemento.datiElemento.tipo !== "testo"
                            anchors.fill: parent
                            color: elemento.datiElemento.colore
                        }

                        FMPortaCampo {
                            visible: elemento.datiElemento.tipo === "porta"
                            anchors.fill: parent
                            colore: elemento.selezionatoQui ? Theme.colors.accent : elemento.datiElemento.coloreContorno
                        }

                        Item {
                            // Il numero va a fianco della sagoma, non sopra
                            // la maglia: coprirebbe il colore scelto. Badge
                            // scuro dietro solo per leggibilita' sul verde
                            // del campo.
                            visible: elemento.datiElemento.tipo === "giocatore" && elemento.datiElemento.mostraEtichetta && coachingBoardVM.mostraEtichetteGlobali && elemento.datiElemento.numero !== ""
                            width: 18; height: 18
                            x: sagomaGiocatore.drawX + sagomaGiocatore.drawW + 2
                            y: sagomaGiocatore.drawY + sagomaGiocatore.drawH / 2 - height / 2
                            Rectangle { anchors.fill: parent; radius: width / 2; color: "#000000"; opacity: 0.5 }
                            Text {
                                anchors.centerIn: parent
                                text: elemento.datiElemento.numero
                                color: "#ffffff"
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.caption
                                font.bold: true
                            }
                        }
                        Text {
                            visible: elemento.datiElemento.tipo === "giocatore" && elemento.datiElemento.mostraEtichetta && coachingBoardVM.mostraEtichetteGlobali && elemento.datiElemento.nomeGiocatore !== ""
                            anchors.top: parent.bottom
                            anchors.topMargin: 2
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: elemento.datiElemento.nomeGiocatore
                            color: Theme.colors.textPrimary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.caption
                        }

                        Text {
                            id: testoVisibile
                            visible: elemento.datiElemento.tipo === "testo"
                            anchors.centerIn: parent
                            text: elemento.datiElemento.testo
                            color: elemento.datiElemento.coloreTesto
                            font.family: Theme.typography.family
                            font.pixelSize: elemento.datiElemento.fontSize
                            font.bold: elemento.datiElemento.grassetto
                        }

                        MouseArea {
                            anchors.fill: parent
                            // Animazione: mentre lo strumento "percorso" e'
                            // armato, questa MouseArea resta abilitata SOLO
                            // per giocatore/pallone - e' l'unico punto da
                            // cui il gesto "traccia un percorso" puo'
                            // partire (segnalato da Luca: "parti dal
                            // giocatore o dal pallone").
                            enabled: root.strumentoAttivo === "" || (root.strumentoAttivo === "percorso" && (datiElemento.tipo === "giocatore" || datiElemento.tipo === "pallone"))
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            // Se l'elemento premuto fa parte di una selezione
                            // multipla, il trascinamento sposta l'intero
                            // gruppo (vedi offsetGruppoX/Y sopra) invece che
                            // solo lui: drag.target va disattivato, altrimenti
                            // il meccanismo automatico di QML scriverebbe
                            // comunque su elemento.x/y da solo. Disattivato
                            // anche durante la cattura di un percorso: il
                            // marcatore non deve spostarsi mentre si disegna
                            // la sua corsa.
                            readonly property bool gruppo: root.selezionati.length > 1 && elemento.selezionatoQui
                            drag.target: (root.strumentoAttivo === "percorso") ? null : (gruppo ? null : elemento)
                            drag.axis: Drag.XAndYAxis
                            property real premutoX: 0
                            property real premutoY: 0
                            property bool mossoInGruppo: false
                            onPressed: function(mouse) {
                                if (root.strumentoAttivo === "percorso") {
                                    var pIniziale = mapToItem(campoTattico, mouse.x, mouse.y)
                                    root.percorsoAncoraId = elemento.datiElemento.id
                                    root.percorsoPuntiAnteprima = [pIniziale]
                                    root.disegnandoPercorso = true
                                    return
                                }
                                premutoX = mouse.x
                                premutoY = mouse.y
                                mossoInGruppo = false
                                if (gruppo) {
                                    root.trascinandoMultiplo = true
                                    root.trascinamentoDx = 0
                                    root.trascinamentoDy = 0
                                }
                            }
                            onPositionChanged: function(mouse) {
                                if (root.disegnandoPercorso) {
                                    // Soglia minima tra un campione e il
                                    // successivo (root.distanzaMinimaCampionamento):
                                    // un drag lungo non deve produrre migliaia
                                    // di punti quasi duplicati.
                                    var pCorrente = mapToItem(campoTattico, mouse.x, mouse.y)
                                    var ultimo = root.percorsoPuntiAnteprima[root.percorsoPuntiAnteprima.length - 1]
                                    if (Math.hypot(pCorrente.x - ultimo.x, pCorrente.y - ultimo.y) >= root.distanzaMinimaCampionamento) {
                                        root.percorsoPuntiAnteprima = root.percorsoPuntiAnteprima.concat([pCorrente])
                                    }
                                    return
                                }
                                // Stesso principio di FMManigliaTrascinamento/
                                // FMFormaLavagna: l'item si sposta insieme
                                // all'offset (vedi binding x/y sopra), quindi
                                // le coordinate locali del mouse si
                                // riallineano ad ogni evento - va accumulato
                                // con += un premutoX/Y MAI riassegnato.
                                if (gruppo && pressed && (mouse.buttons & Qt.LeftButton)) {
                                    root.trascinamentoDx += mouse.x - premutoX
                                    root.trascinamentoDy += mouse.y - premutoY
                                    if (Math.abs(root.trascinamentoDx) > 3 || Math.abs(root.trascinamentoDy) > 3) mossoInGruppo = true
                                }
                            }
                            onClicked: function(mouse) {
                                if (root.strumentoAttivo === "percorso") return
                                if (mossoInGruppo) return  // era un trascinamento di gruppo, non un click di selezione
                                if (mouse.button === Qt.RightButton) {
                                    root.toggleSelezione(elemento.indiceElemento, false)
                                    root.indiceMenuContestuale = elemento.indiceElemento
                                    var overlayIcona = Overlay.overlay
                                    root.apriMenuContestualeA(overlayIcona ? mapToItem(overlayIcona, mouse.x, mouse.y) : null)
                                } else {
                                    root.toggleSelezione(elemento.indiceElemento, mouse.modifiers & Qt.ControlModifier)
                                }
                            }
                            onDoubleClicked: {
                                if (elemento.datiElemento.tipo === "testo") {
                                    dialogoTesto.apriPer(elemento.indiceElemento, elemento.datiElemento.testo, elemento.datiElemento.fontSize, elemento.datiElemento.grassetto, elemento.datiElemento.coloreTesto)
                                }
                            }
                            onReleased: {
                                if (root.disegnandoPercorso) {
                                    root.disegnandoPercorso = false
                                    if (root.percorsoPuntiAnteprima.length >= 2) {
                                        var puntiNormalizzati = root.percorsoPuntiAnteprima.map(function(p) {
                                            return {x: p.x / campoTattico.width, y: p.y / campoTattico.height}
                                        })
                                        coachingBoardVM.aggiungiPercorso(puntiNormalizzati, root.percorsoAncoraId, root.coloreDisegnoAttivo, root.tratteggiatoAttivo, root.spessoreDisegnoAttivo)
                                    }
                                    root.percorsoPuntiAnteprima = []
                                    return
                                }
                                if (root.trascinandoMultiplo) {
                                    var dxNorm = root.trascinamentoDx / campoTattico.width
                                    var dyNorm = root.trascinamentoDy / campoTattico.height
                                    if (dxNorm !== 0 || dyNorm !== 0) {
                                        coachingBoardVM.spostaElementi(root.selezionati, dxNorm, dyNorm)
                                    }
                                    root.trascinandoMultiplo = false
                                    root.trascinamentoDx = 0
                                    root.trascinamentoDy = 0
                                } else {
                                    var nuovaX = (elemento.x + elemento.width / 2) / campoTattico.width
                                    var nuovaY = (elemento.y + elemento.height / 2) / campoTattico.height
                                    coachingBoardVM.spostaElemento(elemento.indiceElemento, nuovaX, nuovaY)
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: coachingBoardVM.elementi
                    delegate: FMFormaLavagna {
                        id: formaDelegate
                        visible: root.eForma(modelData.tipo)
                        z: index
                        indiceForma: index
                        interattivo: root.strumentoAttivo === ""
                        // Il trascinamento individuale di QUESTA forma resta
                        // sospeso mentre e' parte di una selezione multipla
                        // trascinata in gruppo (vedi offsetGruppoX/Y sotto) -
                        // altrimenti seguirebbe due spostamenti in parallelo.
                        // Click/click destro restano sempre attivi.
                        trascinamentoSospeso: root.trascinandoMultiplo && root.isSelezionato(index)
                        tipo: modelData.tipo
                        colore: modelData.colore
                        tratteggiato: modelData.tratteggiato
                        curvatura: modelData.curvatura
                        spessore: modelData.spessore
                        selezionato: root.isSelezionato(index)
                        readonly property real offsetGruppoX: (root.trascinandoMultiplo && root.isSelezionato(index)) ? root.trascinamentoDx : 0
                        readonly property real offsetGruppoY: (root.trascinandoMultiplo && root.isSelezionato(index)) ? root.trascinamentoDy : 0
                        p1: Qt.point(modelData.x1 * campoTattico.width + offsetGruppoX, modelData.y1 * campoTattico.height + offsetGruppoY)
                        p2: Qt.point(modelData.x2 * campoTattico.width + offsetGruppoX, modelData.y2 * campoTattico.height + offsetGruppoY)
                        onRichiestaSelezione: function(indice, ctrl) { root.toggleSelezione(indice, ctrl) }
                        onRichiestaMenuContestuale: function(indice) {
                            root.indiceMenuContestuale = indice
                            var overlayForma = Overlay.overlay
                            root.apriMenuContestualeA(overlayForma ? formaDelegate.mapToItem(overlayForma, 0, formaDelegate.height) : null)
                        }
                        onSpostata: function(indice, dxPx, dyPx) {
                            var el = coachingBoardVM.elementi[indice]
                            coachingBoardVM.spostaForma(
                                indice,
                                el.x1 + dxPx / campoTattico.width, el.y1 + dyPx / campoTattico.height,
                                el.x2 + dxPx / campoTattico.width, el.y2 + dyPx / campoTattico.height
                            )
                        }
                        onCurvaturaCambiata: function(indice, curvatura) { coachingBoardVM.impostaCurvaturaForma(indice, curvatura) }
                    }
                }

                // Percorsi di movimento (Animazione): stesso principio delle
                // forme sopra, geometria a N punti invece di due.
                Repeater {
                    model: coachingBoardVM.elementi
                    delegate: FMPercorsoLavagna {
                        id: percorsoDelegate
                        // Fuori da Modalita' Animazione la curva non si vede:
                        // e' una guida per il movimento, non un segno
                        // permanente sulla lavagna tattica statica (Luca:
                        // "rimane sempre visibile" era il bug).
                        visible: modelData.tipo === "percorso" && root.modalitaAnimazione
                        z: index
                        indicePercorso: index
                        interattivo: root.strumentoAttivo === ""
                        colore: modelData.colore
                        tratteggiato: modelData.tratteggiato
                        spessore: modelData.spessore
                        selezionato: root.isSelezionato(index)
                        readonly property real offsetGruppoX: (root.trascinandoMultiplo && root.isSelezionato(index)) ? root.trascinamentoDx : 0
                        readonly property real offsetGruppoY: (root.trascinandoMultiplo && root.isSelezionato(index)) ? root.trascinamentoDy : 0
                        punti: modelData.tipo === "percorso" ? modelData.punti.map(function(p) {
                            return {x: p.x * campoTattico.width + offsetGruppoX, y: p.y * campoTattico.height + offsetGruppoY}
                        }) : []
                        onRichiestaSelezione: function(indice, ctrl) { root.toggleSelezione(indice, ctrl) }
                        onRichiestaMenuContestuale: function(indice) {
                            root.indiceMenuContestuale = indice
                            var overlayPercorso = Overlay.overlay
                            root.apriMenuContestualeA(overlayPercorso ? percorsoDelegate.mapToItem(overlayPercorso, 0, percorsoDelegate.height) : null)
                        }
                    }
                }
            }
            }
        }
        }

        // ------------------------------------------------------------
        // Separatore orizzontale, drag verticale: regola root.altezzaBarraInferiore
        // (min/max sopra). Stessa tecnica del separatoreSidebar laterale -
        // mouse.y rimappato su colonnaPrincipale (che non si muove) invece
        // che letto localmente, altrimenti il drag scatta perche' questo
        // Item si riposiziona ogni frame appena barraInferiore cambia altezza.
        // ------------------------------------------------------------
        Item {
            id: separatoreInferiore
            width: parent.width
            height: 8

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 2
                radius: 1
                color: Theme.colors.border
                opacity: areaSeparatoreInferiore.containsMouse || areaSeparatoreInferiore.pressed ? 0.9 : 0.35
            }

            MouseArea {
                id: areaSeparatoreInferiore
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: Qt.SizeVerCursor
                property real yPressStart: 0
                property real altezzaPressStart: 0
                onPressed: function(mouse) {
                    var p = areaSeparatoreInferiore.mapToItem(colonnaPrincipale, mouse.x, mouse.y)
                    yPressStart = p.y
                    altezzaPressStart = root.altezzaBarraInferiore
                }
                onPositionChanged: function(mouse) {
                    if (!areaSeparatoreInferiore.pressed) return
                    var p = areaSeparatoreInferiore.mapToItem(colonnaPrincipale, mouse.x, mouse.y)
                    // Trascinare verso il basso allontana il separatore da
                    // barraInferiore -> deve CRESCERE (segno invertito
                    // rispetto a un delta letto verso l'alto).
                    var delta = yPressStart - p.y
                    root.altezzaBarraInferiore = Math.max(root.altezzaBarraInferioreMinima, Math.min(root.altezzaBarraInferioreMassima, altezzaPressStart + delta))
                }
            }
        }

        // ------------------------------------------------------------
        // Barra inferiore: pulsanti di uso costante (aggiungi elementi,
        // strumenti disegno), a piena larghezza sotto al campo - altezza
        // regolabile tramite separatoreInferiore sopra (default: naturale,
        // contenutoInferiore.implicitHeight, come prima), con scroll
        // verticale quando ridotta sotto il contenuto.
        // ------------------------------------------------------------
        Flickable {
            id: barraInferiore
            width: parent.width
            height: root.altezzaBarraInferiore
            contentWidth: contenutoInferiore.implicitWidth
            contentHeight: contenutoInferiore.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            Row {
                id: contenutoInferiore
                spacing: Theme.spacing.lg

                FMCard {
                    width: 620
                    title: "Aggiungi elementi"

                    Column {
                        width: parent.width
                        // Ridotto da sm a xs (Luca: barra comandi troppo
                        // ingombrante rispetto al campo) - spaziatura piu'
                        // stretta tra le righe di pulsanti, nessun cambio di
                        // dimensione dei pulsanti stessi (componente
                        // condiviso FMButton, usato in tutto il programma).
                        spacing: Theme.spacing.xs

                        Text { text: "Giocatori"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            FMButton { text: "+ Sq 1"; onClicked: coachingBoardVM.aggiungiElemento("giocatore", 0.5, 0.5, root.coloreMagliaSquadraA, "a") }
                            FMButton { text: "+ Sq 2"; onClicked: coachingBoardVM.aggiungiElemento("giocatore", 0.5, 0.5, root.coloreMagliaSquadraB, "b") }
                            FMButton { text: "+ Port 1"; onClicked: coachingBoardVM.aggiungiElemento("giocatore", 0.5, 0.5, "#2f9e44", "a") }
                            FMButton { text: "+ Port 2"; onClicked: coachingBoardVM.aggiungiElemento("giocatore", 0.5, 0.5, "#ffd400", "b") }
                        }

                        Text { text: "Oggetti"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            FMButton { text: "+ Pallone"; onClicked: coachingBoardVM.aggiungiElemento("pallone", 0.5, 0.5, "", "") }
                            FMButton { text: "+ Porta"; onClicked: coachingBoardVM.aggiungiElemento("porta", 0.5, 0.05, "", "") }
                            FMButton { text: "+ Testo"; onClicked: coachingBoardVM.aggiungiElemento("testo", 0.5, 0.5, "", "") }
                            FMButton { text: "+ Cono"; onClicked: coachingBoardVM.aggiungiElemento("cono", 0.5, 0.5, "", "") }
                            FMButton { text: "+ Conetto"; onClicked: coachingBoardVM.aggiungiElemento("conetto", 0.5, 0.5, "#f5a45c", "") }
                            FMButton { text: "+ Palo"; onClicked: coachingBoardVM.aggiungiElemento("palo", 0.5, 0.5, "#f4f6fb", "") }
                            FMButton { text: "+ Scaletta"; onClicked: coachingBoardVM.aggiungiElemento("scaletta", 0.5, 0.5, "#f4f6fb", "") }
                            FMButton { text: "+ Cerchio"; onClicked: coachingBoardVM.aggiungiElemento("cerchio", 0.5, 0.5, "#f4f6fb", "") }
                        }

                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            FMButton {
                                text: "Duplica selezionato"
                                enabled: root.selezionato !== -1
                                onClicked: coachingBoardVM.duplicaElemento(root.selezionato)
                            }
                            FMButton {
                                destructive: true
                                text: root.selezionati.length > 1 ? "Elimina selezionati (" + root.selezionati.length + ")" : "Rimuovi selezionato"
                                enabled: root.selezionati.length > 0
                                onClicked: dialogoConfermaEliminazione.apri(
                                    "Elimina elementi",
                                    "Rimuovere " + root.selezionati.length + " elemento/i selezionato/i dalla lavagna?",
                                    "Elimina",
                                    function() { coachingBoardVM.rimuoviElementi(root.selezionati); root.deselezionaTutto() }
                                )
                            }
                        }
                    }
                }

                FMCard {
                    width: 480
                    title: "Strumenti disegno"

                    Column {
                        width: parent.width
                        spacing: Theme.spacing.xs

                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            Repeater {
                                model: [
                                    {v: "freccia", l: "Freccia"}, {v: "linea", l: "Linea"},
                                    {v: "frecciaCurva", l: "Freccia curva"}, {v: "lineaCurva", l: "Linea curva"},
                                    {v: "rettVuoto", l: "Rett. Vuoto"}, {v: "rettPieno", l: "Rett. Pieno"},
                                    {v: "ellisseV", l: "Ellisse V"}, {v: "ellisseP", l: "Ellisse P"},
                                ]
                                delegate: FMButton {
                                    text: modelData.l
                                    primary: root.strumentoAttivo === modelData.v
                                    onClicked: {
                                        // Ricliccare lo strumento gia' attivo lo disattiva
                                        // (torna a selezionare/spostare gli elementi).
                                        root.strumentoAttivo = (root.strumentoAttivo === modelData.v) ? "" : modelData.v
                                        root.deselezionaTutto()
                                    }
                                }
                            }
                        }
                        Flow {
                            width: parent.width
                            spacing: Theme.spacing.xs
                            FMButton { text: "Continuo"; primary: !root.tratteggiatoAttivo; onClicked: root.tratteggiatoAttivo = false }
                            FMButton { text: "Tratteggiato"; primary: root.tratteggiatoAttivo; onClicked: root.tratteggiatoAttivo = true }
                            FMSelettoreColore { coloreAttuale: root.coloreDisegnoAttivo; onColorScelto: function(c) { root.coloreDisegnoAttivo = c; coachingBoardVM.scriviImpostazione("coloreDisegno", c) } }
                        }
                        Text { text: "Spessore (" + root.spessoreDisegnoAttivo.toFixed(0) + "px)"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                        Slider { width: parent.width; from: 1; to: 8; stepSize: 1; value: root.spessoreDisegnoAttivo; onMoved: { root.spessoreDisegnoAttivo = value; coachingBoardVM.scriviImpostazione("spessoreDisegno", "" + value) } }
                        Text {
                            visible: root.strumentoAttivo !== ""
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: "Tieni premuto e trascina sul campo per disegnare. Esc per uscire dallo strumento."
                            color: Theme.colors.textTertiary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.caption
                        }
                    }
                }
            }
        }
    }

    Menu {
        id: menuContestuale
        MenuItem {
            text: "Porta avanti"
            onTriggered: {
                var nuovoIndice = coachingBoardVM.portaAvanti(root.indiceMenuContestuale)
                if (nuovoIndice !== -1) { root.selezionato = nuovoIndice; root.selezionati = [nuovoIndice] }
            }
        }
        MenuItem {
            text: "Porta indietro"
            onTriggered: {
                var nuovoIndice = coachingBoardVM.portaIndietro(root.indiceMenuContestuale)
                if (nuovoIndice !== -1) { root.selezionato = nuovoIndice; root.selezionati = [nuovoIndice] }
            }
        }
        MenuItem { text: "Duplica"; onTriggered: coachingBoardVM.duplicaElemento(root.indiceMenuContestuale) }
        MenuItem { text: "+ Testo ancorato qui"; onTriggered: coachingBoardVM.aggiungiTestoAncorato(root.indiceMenuContestuale) }
        MenuSeparator {}
        MenuItem {
            text: "Rimuovi"
            onTriggered: dialogoConfermaEliminazione.apri(
                "Elimina elemento",
                "Rimuovere questo elemento dalla lavagna?",
                "Elimina",
                function() { coachingBoardVM.rimuoviElemento(root.indiceMenuContestuale); root.deselezionaTutto() }
            )
        }
    }

    FMTestoElementoDialog {
        id: dialogoTesto
        onApplica: function(indice, testo, fontSize, grassetto, colore) {
            coachingBoardVM.impostaTestoElemento(indice, testo)
            coachingBoardVM.impostaFontSizeTesto(indice, fontSize)
            coachingBoardVM.impostaGrassettoTesto(indice, grassetto)
            coachingBoardVM.impostaColoreTesto(indice, colore)
        }
    }

    FMConfirmDialog { id: dialogoConfermaEliminazione }

    // Animazione: destinazione della GIF esportata - lo stesso pattern
    // "FileDialog di salvataggio" gia' usato altrove nel programma (es.
    // esportazione PDF), cosi' Luca sceglie dove salvare per condividerla
    // invece di un percorso automatico nascosto.
    FileDialog {
        id: dialogoEsportaAnimazione
        title: "Esporta animazione come GIF"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Animazione GIF (*.gif)"]
        onAccepted: {
            var destinazione = root.urlAPercorso(dialogoEsportaAnimazione.selectedFile)
            if (destinazione.toLowerCase().indexOf(".gif") !== destinazione.length - 4) destinazione += ".gif"
            root._destinazioneEsportazione = destinazione
            root.fotogrammaEsportazione = 0
            root.totaleFotogrammiEsportazione = Math.ceil(root.durataTotaleAnimazione * root.fpsEsportazione) + 1
            root._fotogrammiCatturati = []
            root.inRiproduzione = false
            root.esportazioneInCorso = true
            root.catturaProssimoFotogramma()
        }
    }

    Popup {
        id: popupColoreSfondo
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        padding: Theme.spacing.md
        background: Rectangle {
            color: Theme.colors.bgSurface; radius: Theme.radius.lg; border.width: 1; border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: popupColoreSfondo }
        }
        Overlay.modal: Rectangle { color: "#000000aa" }
        contentItem: FMSelettoreColore {
            coloreAttuale: coachingBoardVM.coloreCampo
            onColorScelto: function(c) { coachingBoardVM.impostaColoreCampo(c); popupColoreSfondo.close() }
        }
    }
    Popup {
        id: popupColoreLinee
        parent: Overlay.overlay
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        padding: Theme.spacing.md
        background: Rectangle {
            color: Theme.colors.bgSurface; radius: Theme.radius.lg; border.width: 1; border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: popupColoreLinee }
        }
        Overlay.modal: Rectangle { color: "#000000aa" }
        contentItem: FMSelettoreColore {
            coloreAttuale: coachingBoardVM.coloreLinee
            onColorScelto: function(c) { coachingBoardVM.impostaColoreLinee(c); popupColoreLinee.close() }
        }
    }

    // Pannello Animazione: prima era una riga fissa incollata sotto al
    // campo, "occupava tanto spazio e limitava lo spazio di lavoro"
    // (segnalato da Luca) - ora e' un Popup flottante, spostabile su tutto
    // lo schermo (FMManigliaTrascinamento, stesso pattern dei popup colore
    // sopra) e NON modale: a differenza di quelli, deve restare visibile
    // mentre si continua a disegnare/trascinare sul campo sottostante,
    // quindi niente overlay che scurisce lo sfondo e niente
    // CloseOnPressOutside (altrimenti un click sul campo per disegnare un
    // percorso lo chiuderebbe). Si chiude solo col pulsante "×" o
    // ridisattivando "Modalità Animazione" in sidebar.
    Popup {
        id: popupAnimazione
        parent: Overlay.overlay
        visible: root.modalitaAnimazione
        modal: false
        focus: false
        closePolicy: Popup.NoAutoClose
        x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
        // Mai piu' grande dello schermo disponibile, anche se
        // root.larghezzaPopupAnimazione/altezzaPopupAnimazione (la misura
        // "voluta" dall'ultimo trascinamento della maniglia) lo sarebbe.
        width: Overlay.overlay ? Math.min(root.larghezzaPopupAnimazione, Overlay.overlay.width - 40) : root.larghezzaPopupAnimazione
        height: Overlay.overlay ? Math.min(root.altezzaPopupAnimazione, Overlay.overlay.height - 60) : root.altezzaPopupAnimazione
        padding: Theme.spacing.md
        background: Rectangle {
            color: Theme.colors.bgSurface; radius: Theme.radius.lg; border.width: 1; border.color: Theme.colors.border
            FMManigliaTrascinamento { bersaglio: popupAnimazione }

            // Maniglia di ridimensionamento, angolo in basso a destra:
            // stessa tecnica drag di FMManigliaTrascinamento (mouse.x/y
            // rimappati su Overlay.overlay, che non si muove, invece che
            // letti localmente - la maniglia stessa si riposiziona ogni
            // frame appena il popup cambia dimensione durante il drag).
            Item {
                id: manigliaRidimensionamento
                width: 16
                height: 16
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                Row {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 3
                    rotation: -45
                    spacing: 2
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            width: 3; height: 3; radius: 1.5
                            color: areaRidimensionamento.containsMouse || areaRidimensionamento.pressed ? Theme.colors.textSecondary : Theme.colors.textTertiary
                        }
                    }
                }

                MouseArea {
                    id: areaRidimensionamento
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: Qt.SizeFDiagCursor
                    property real xPressStart: 0
                    property real yPressStart: 0
                    property real larghezzaPressStart: 0
                    property real altezzaPressStart: 0
                    onPressed: function(mouse) {
                        var p = areaRidimensionamento.mapToItem(Overlay.overlay, mouse.x, mouse.y)
                        xPressStart = p.x
                        yPressStart = p.y
                        larghezzaPressStart = root.larghezzaPopupAnimazione
                        altezzaPressStart = root.altezzaPopupAnimazione
                    }
                    onPositionChanged: function(mouse) {
                        if (!areaRidimensionamento.pressed) return
                        var p = areaRidimensionamento.mapToItem(Overlay.overlay, mouse.x, mouse.y)
                        root.larghezzaPopupAnimazione = Math.max(root.larghezzaPopupAnimazioneMinima, Math.min(root.larghezzaPopupAnimazioneMassima, larghezzaPressStart + (p.x - xPressStart)))
                        root.altezzaPopupAnimazione = Math.max(root.altezzaPopupAnimazioneMinima, Math.min(root.altezzaPopupAnimazioneMassima, altezzaPressStart + (p.y - yPressStart)))
                    }
                }
            }
        }

        contentItem: Flickable {
            id: flickAnimazionePopup
            clip: true
            width: popupAnimazione.availableWidth
            height: popupAnimazione.availableHeight
            contentWidth: width
            contentHeight: contenutoAnimazione.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            FMCard {
                id: contenutoAnimazione
                width: parent.width
                title: "Animazione"

                Column {
                    width: parent.width
                    spacing: Theme.spacing.sm

                    Flow {
                        width: parent.width
                        spacing: Theme.spacing.xs
                        FMButton {
                            text: "Traccia percorso"
                            primary: root.strumentoAttivo === "percorso"
                            onClicked: {
                                root.strumentoAttivo = (root.strumentoAttivo === "percorso") ? "" : "percorso"
                                root.deselezionaTutto()
                            }
                        }
                        FMButton {
                            text: root.inRiproduzione ? "Pausa" : "▶ Play"
                            enabled: root.durataTotaleAnimazione > 0
                            onClicked: {
                                if (!root.inRiproduzione && root.progressoAnimazione >= root.durataTotaleAnimazione) root.progressoAnimazione = 0
                                root.inRiproduzione = !root.inRiproduzione
                            }
                        }
                        FMButton {
                            text: "Stop"
                            onClicked: { root.inRiproduzione = false; root.progressoAnimazione = 0 }
                        }
                        FMButton {
                            text: "Esporta animazione…"
                            enabled: root.durataTotaleAnimazione > 0 && !root.esportazioneInCorso
                            onClicked: dialogoEsportaAnimazione.open()
                        }
                        FMButton {
                            text: "× Chiudi"
                            onClicked: { root.modalitaAnimazione = false; root.inRiproduzione = false; root.strumentoAttivo = "" }
                        }
                    }

                    Text { text: "Mostra percorsi durante il playback"; color: Theme.colors.textSecondary; font.family: Theme.typography.family; font.pixelSize: Theme.typography.caption; font.bold: true }
                    Flow {
                        width: parent.width
                        spacing: Theme.spacing.xs
                        FMButton { text: "Squadra 1"; primary: root.squadreVisibili.a; onClicked: root.impostaVisibilitaSquadra("a", !root.squadreVisibili.a) }
                        FMButton { text: "Squadra 2"; primary: root.squadreVisibili.b; onClicked: root.impostaVisibilitaSquadra("b", !root.squadreVisibili.b) }
                        FMButton { text: "Pallone"; primary: root.squadreVisibili.pallone; onClicked: root.impostaVisibilitaSquadra("pallone", !root.squadreVisibili.pallone) }
                    }

                    Row {
                        width: parent.width
                        spacing: Theme.spacing.sm
                        Text {
                            width: 100
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.progressoAnimazione.toFixed(1) + "s / " + root.durataTotaleAnimazione.toFixed(1) + "s"
                            color: Theme.colors.textSecondary
                            font.family: Theme.typography.family
                            font.pixelSize: Theme.typography.caption
                        }
                        Slider {
                            width: parent.width - 110
                            from: 0; to: Math.max(0.001, root.durataTotaleAnimazione)
                            value: root.progressoAnimazione
                            onMoved: { root.inRiproduzione = false; root.progressoAnimazione = value }
                        }
                    }

                    Text {
                        visible: root.esportazioneInCorso
                        text: "Esportazione: " + root.fotogrammaEsportazione + "/" + root.totaleFotogrammiEsportazione + " fotogrammi…"
                        color: Theme.colors.accent
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.caption
                    }

                    Text {
                        visible: coachingBoardVM.elementi.filter(function(e) { return e.tipo === "percorso" }).length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: "Nessun percorso disegnato. Attiva \"Traccia percorso\" e trascina da un giocatore o dal pallone."
                        color: Theme.colors.textTertiary
                        font.family: Theme.typography.family
                        font.pixelSize: Theme.typography.caption
                    }

                    // Una riga per ogni percorso: barra trascinabile su un
                    // righello temporale 0..durataTotaleAnimazione -
                    // trascinare il corpo regola il ritardo, la maniglia sul
                    // bordo destro regola la durata. Stesso pattern
                    // anteprima-poi-commit-al-rilascio gia' usato dalla
                    // maniglia di curvatura in FMFormaLavagna.
                    Repeater {
                        model: coachingBoardVM.elementi
                        delegate: Item {
                            visible: modelData.tipo === "percorso"
                            width: parent.width
                            height: 34

                            readonly property var ancora: {
                                for (var i = 0; i < coachingBoardVM.elementi.length; i++) {
                                    if (coachingBoardVM.elementi[i].id === modelData.ancoraId) return coachingBoardVM.elementi[i]
                                }
                                return null
                            }
                            readonly property string etichetta: {
                                if (!ancora) return "Percorso"
                                if (ancora.tipo === "pallone") return "Pallone"
                                return ancora.nomeGiocatore || (ancora.numero ? ("Giocatore #" + ancora.numero) : "Giocatore")
                            }

                            Text {
                                width: 110
                                anchors.verticalCenter: parent.verticalCenter
                                text: etichetta
                                elide: Text.ElideRight
                                color: Theme.colors.textPrimary
                                font.family: Theme.typography.family
                                font.pixelSize: Theme.typography.small
                            }

                            Rectangle {
                                id: binarioTimeline
                                x: 116
                                width: parent.width - 116 - 34
                                height: 22
                                anchors.verticalCenter: parent.verticalCenter
                                radius: Theme.radius.sm
                                color: Theme.colors.bgSurface2
                                border.width: 1
                                border.color: Theme.colors.border

                                readonly property real scala: root.durataTotaleAnimazione > 0 ? width / root.durataTotaleAnimazione : 0

                                Rectangle {
                                    id: barraPercorso
                                    property bool trascinandoCorpo: false
                                    property real ritardoAnteprima: modelData.ritardo
                                    property bool trascinandoDurata: false
                                    property real durataAnteprima: modelData.durata
                                    readonly property real ritardoEff: trascinandoCorpo ? ritardoAnteprima : modelData.ritardo
                                    readonly property real durataEff: trascinandoDurata ? durataAnteprima : modelData.durata

                                    x: ritardoEff * binarioTimeline.scala
                                    width: Math.max(6, durataEff * binarioTimeline.scala)
                                    height: parent.height
                                    radius: Theme.radius.sm
                                    color: root.isSelezionato(index) ? Theme.colors.accent : Theme.colors.primario
                                    opacity: 0.85

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.rightMargin: 8
                                        property real premutoX: 0
                                        onPressed: function(mouse) { premutoX = mouse.x; barraPercorso.trascinandoCorpo = true; barraPercorso.ritardoAnteprima = modelData.ritardo }
                                        onPositionChanged: function(mouse) {
                                            if (!barraPercorso.trascinandoCorpo || binarioTimeline.scala <= 0) return
                                            var deltaSecondi = (mouse.x - premutoX) / binarioTimeline.scala
                                            barraPercorso.ritardoAnteprima = Math.max(0, modelData.ritardo + deltaSecondi)
                                        }
                                        onReleased: {
                                            barraPercorso.trascinandoCorpo = false
                                            coachingBoardVM.impostaRitardoPercorso(index, barraPercorso.ritardoAnteprima)
                                        }
                                        onClicked: root.toggleSelezione(index, false)
                                    }

                                    Rectangle {
                                        width: 8
                                        height: parent.height
                                        anchors.right: parent.right
                                        color: "transparent"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.SizeHorCursor
                                            property real premutoX: 0
                                            onPressed: function(mouse) { premutoX = mouse.x; barraPercorso.trascinandoDurata = true; barraPercorso.durataAnteprima = modelData.durata }
                                            onPositionChanged: function(mouse) {
                                                if (!barraPercorso.trascinandoDurata || binarioTimeline.scala <= 0) return
                                                var deltaSecondi2 = (mouse.x - premutoX) / binarioTimeline.scala
                                                barraPercorso.durataAnteprima = Math.max(0.2, modelData.durata + deltaSecondi2)
                                            }
                                            onReleased: {
                                                barraPercorso.trascinandoDurata = false
                                                coachingBoardVM.impostaDurataPercorso(index, barraPercorso.durataAnteprima)
                                            }
                                        }
                                    }
                                }
                            }

                            FMButton {
                                width: 34
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: parent.right
                                destructive: true
                                text: "×"
                                onClicked: dialogoConfermaEliminazione.apri(
                                    "Elimina percorso",
                                    "Rimuovere questo percorso di movimento?",
                                    "Elimina",
                                    function() { coachingBoardVM.rimuoviElemento(index); root.deselezionaTutto() }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
