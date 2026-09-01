import QtQuick
import QtQuick.Controls.Basic
import Theme

// ComboBox a tema scuro coerente col resto del programma. Lo stile Basic di
// Qt Quick Controls lascia la lista a discesa (popup) bianca di default
// anche quando si personalizzano solo "background"/"contentItem" del box
// chiuso (coprono solo quello, non il popup) - segnalato da Luca come "un
// pugno nell'occhio". Sostituisce ComboBox ovunque nel programma: stessa
// API (editable, model, textRole, currentIndex, editText, onXxx...), cambia
// solo l'aspetto.
ComboBox {
    id: root

    font.family: Theme.typography.family
    font.pixelSize: Theme.typography.body
    implicitHeight: 34

    background: Rectangle {
        implicitHeight: 34
        color: Theme.colors.bgSurface2
        radius: Theme.radius.sm
        border.width: 1
        border.color: root.activeFocus ? Theme.colors.accent : Theme.colors.border
    }

    // TextField (non un semplice Text) anche quando non editabile, stesso
    // principio dello stile Basic upstream: un solo contentItem gestisce
    // sia il caso editable (editText) sia quello sola-lettura (displayText),
    // senza reimplementare a mano il binding bidirezionale su editText.
    contentItem: TextField {
        text: root.editable ? root.editText : root.displayText
        enabled: root.editable
        readOnly: !root.editable
        leftPadding: Theme.spacing.sm
        rightPadding: root.indicator.width + Theme.spacing.sm
        color: Theme.colors.textPrimary
        font: root.font
        verticalAlignment: Text.AlignVCenter
        background: Item {}
        // BUG (segnalato da Luca): senza questo, digitare in un ComboBox
        // editable (Mezzo/Obiettivo tecnico/Obiettivo tattico in Sedute)
        // aggiornava solo il testo VISIBILE di questo TextField - mai
        // root.editText - perche' "text: root.editable ? root.editText :
        // ..." e' un binding a senso unico: appena l'utente digita,
        // TextInput assegna "text" imperativamente e rompe quel binding, ma
        // niente riscriveva root.editText. A valle, onEditTextChanged non
        // scattava mai piu' e nulla veniva salvato: sembrava un campo di
        // testo libero scollegato dal ComboBox, non un menu a tendina.
        onTextEdited: if (root.editable) root.editText = text
    }

    // Freccia in un Item con MouseArea propria (non un Text nudo): un Text
    // non intercetta click, quindi con un ComboBox editable il TextField
    // sottostante copriva comunque tutta l'area (frecca inclusa) e il
    // popup non si apriva piu' cliccando la freccia - "non e' piu' un menu
    // a tendina, ci scrivi dentro" (segnalato da Luca). Dichiarata DOPO
    // contentItem, quindi sta sopra nello z-order e riceve il click prima
    // del TextField sotto.
    indicator: Item {
        x: root.width - width - Theme.spacing.sm
        y: 0
        width: freccia.implicitWidth + Theme.spacing.sm
        height: root.height
        Text {
            id: freccia
            anchors.centerIn: parent
            text: "▾"
            color: Theme.colors.textSecondary
            font.pixelSize: Theme.typography.small
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.popup.visible ? root.popup.close() : root.popup.open()
        }
    }

    delegate: ItemDelegate {
        id: riga
        width: root.width
        highlighted: root.highlightedIndex === index
        background: Rectangle {
            color: riga.highlighted ? Theme.colors.bgSurface3 : Theme.colors.bgSurface2
        }
        contentItem: Text {
            leftPadding: Theme.spacing.sm
            text: root.textRole !== "" && modelData !== undefined && modelData !== null && typeof modelData === "object"
                ? modelData[root.textRole] : modelData
            color: Theme.colors.textPrimary
            font: root.font
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }

    popup: Popup {
        y: root.height + 2
        width: root.width
        implicitHeight: Math.min(listaOpzioni.contentHeight + 2, 320)
        padding: 1

        background: Rectangle {
            color: Theme.colors.bgSurface2
            border.width: 1
            border.color: Theme.colors.border
            radius: Theme.radius.sm
        }

        contentItem: ListView {
            id: listaOpzioni
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
