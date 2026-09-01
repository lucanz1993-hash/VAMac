import QtQuick
import QtQuick.Controls.Basic
import Theme

// Popup di conferma riutilizzabile, per ogni azione distruttiva dell'app
// (elimina giocatore, elimina lavagna, scollega seduta, ecc.). Prima di
// questo componente nessuna schermata chiedeva conferma prima di cancellare
// qualcosa: una singola istanza per schermata, azionata da apri(...), evita
// di duplicare lo stesso popup in ogni punto che elimina qualcosa.
Popup {
    id: root
    // Senza reparent esplicito, x/y sotto restano relativi al parent QML di
    // dichiarazione: per le istanze dichiarate poco profonde (root di uno
    // screen) coincide quasi con l'origine finestra e sembra funzionare per
    // caso, ma per istanze annidate in profondita' (es. dentro
    // FMEditorImmagineEsercizio, a sua volta dentro un Repeater/Column/Row/
    // FMCard scorrevole) la formula di centratura calcolata su
    // Overlay.overlay veniva applicata all'origine SBAGLIATA: il dialogo
    // finiva fuori schermo, sembrando "non funzionare" (es. "Rimuovi
    // immagine" - segnalato da Luca). Riparentare qui, una volta sola nel
    // componente condiviso, risolve ogni istanza presente e futura.
    parent: Overlay.overlay
    modal: true
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    x: Overlay.overlay ? Math.max(0, (Overlay.overlay.width - width) / 2) : 0
    y: Overlay.overlay ? Math.max(0, (Overlay.overlay.height - height) / 2) : 0
    width: 420
    padding: Theme.spacing.lg

    property string titolo: "Conferma"
    property string messaggio: ""
    property string testoConferma: "Conferma"
    property bool distruttivo: true
    // Funzione JS eseguita alla conferma, impostata da chi apre il dialogo
    // (vedi apri()): un singolo Popup condiviso non puo' sapere in anticipo
    // quale azione confermare, quindi la riceve al volo ad ogni apertura.
    property var azione: null

    function apri(titoloDialogo, messaggioDialogo, testoConfermaDialogo, azioneDialogo, distruttivoDialogo) {
        root.titolo = titoloDialogo
        root.messaggio = messaggioDialogo
        root.testoConferma = testoConfermaDialogo !== undefined ? testoConfermaDialogo : "Conferma"
        root.azione = azioneDialogo
        root.distruttivo = distruttivoDialogo !== undefined ? distruttivoDialogo : true
        root.open()
    }

    // Invio (principale o tastierino numerico) equivale al click sul
    // pulsante di conferma: prima il popup si chiudeva solo con Annulla,
    // click su "Sì" o Esc - Invio non faceva nulla, costringendo sempre al
    // mouse anche per l'azione piu' frequente (confermare). "Keys" e'
    // un'attached property valida solo su un Item: Popup non lo e' (e'
    // una QQuickPopup), va messa sul suo contentItem sotto.
    function confermaEInvio() {
        if (root.azione) root.azione()
        root.close()
    }

    background: Rectangle {
        color: Theme.colors.bgSurface
        radius: Theme.radius.lg
        border.width: 1
        border.color: Theme.colors.border
        FMManigliaTrascinamento { bersaglio: root }
    }

    Overlay.modal: Rectangle {
        color: "#000000aa"
    }

    contentItem: Column {
        width: root.width - root.padding * 2
        spacing: Theme.spacing.md
        focus: true
        Keys.onReturnPressed: root.confermaEInvio()
        Keys.onEnterPressed: root.confermaEInvio()

        Text {
            text: root.titolo
            color: Theme.colors.textPrimary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.title
            font.bold: true
        }
        Text {
            width: parent.width
            text: root.messaggio
            wrapMode: Text.WordWrap
            color: Theme.colors.textSecondary
            font.family: Theme.typography.family
            font.pixelSize: Theme.typography.body
        }
        Item {
            width: parent.width
            height: btnConferma.height

            FMButton {
                anchors.left: parent.left
                text: "Annulla"
                onClicked: root.close()
            }
            FMButton {
                id: btnConferma
                anchors.right: parent.right
                text: root.testoConferma
                destructive: root.distruttivo
                primary: !root.distruttivo
                onClicked: root.confermaEInvio()
            }
        }
    }
}
