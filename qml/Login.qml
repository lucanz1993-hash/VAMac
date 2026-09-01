import QtQuick
import QtQuick.Controls.Basic
import Theme
import "components"

ApplicationWindow {
    id: root
    width: 460
    height: 620
    minimumWidth: 460
    minimumHeight: 620
    visible: true
    title: "FC Manager — Accesso"
    color: Theme.colors.bgMain

    property bool modalitaRegistrazione: false

    // FIX: prima era un Rectangle senza altezza esplicita (color:
    // "transparent", solo per centrare) attorno a questa Column: un
    // Rectangle senza figli che gli impongano l'altezza resta a height:0,
    // quindi anchors.centerIn: parent lo centrava usando un'altezza di 0
    // invece della vera altezza del contenuto (~350px). Il contenuto
    // continuava comunque a essere disegnato oltre i bordi del Rectangle,
    // ma "Continua senza connessione" (l'unico modo per accedere offline)
    // finiva quasi interamente sotto il bordo inferiore della finestra
    // 460x620 di default, invisibile finche' l'utente non allargava la
    // finestra a mano. Centrare direttamente questa Column (che ha
    // un'altezza implicita corretta, basata sul suo contenuto) risolve alla
    // radice, senza il contenitore intermedio.
    Column {
        anchors.centerIn: parent
        width: 380
        spacing: Theme.spacing.xl

        Column {
            width: parent.width
            spacing: Theme.spacing.xs
            Text {
                text: "FC MANAGER"
                color: Theme.colors.textPrimary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.display
                font.bold: true
                anchors.horizontalCenter: parent.horizontalCenter
            }
            Text {
                text: root.modalitaRegistrazione ? "Crea un nuovo account" : "Accedi al tuo account"
                color: Theme.colors.textSecondary
                font.family: Theme.typography.family
                font.pixelSize: Theme.typography.body
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }

        FMCard {
            width: parent.width

            Column {
                width: parent.width
                spacing: Theme.spacing.md

                TextField {
                    id: campoNome
                    visible: root.modalitaRegistrazione
                    width: parent.width
                    placeholderText: "Nome e cognome"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                TextField {
                    id: campoEmail
                    width: parent.width
                    placeholderText: "Email"
                    placeholderTextColor: Theme.colors.textSecondary
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }
                TextField {
                    id: campoPassword
                    width: parent.width
                    placeholderText: "Password"
                    placeholderTextColor: Theme.colors.textSecondary
                    echoMode: TextInput.Password
                    color: Theme.colors.textPrimary
                    font.family: Theme.typography.family
                    background: Rectangle { color: Theme.colors.bgSurface2; radius: Theme.radius.sm; border.width: 1; border.color: Theme.colors.border }
                }

                Text {
                    visible: loginVM.errore !== ""
                    text: loginVM.errore
                    color: Theme.colors.danger
                    wrapMode: Text.WordWrap
                    width: parent.width
                    font.family: Theme.typography.family
                    font.pixelSize: Theme.typography.small
                }

                FMButton {
                    width: parent.width
                    primary: true
                    text: loginVM.caricamento ? "..." : (root.modalitaRegistrazione ? "Registrati" : "Accedi")
                    enabled: !loginVM.caricamento
                    onClicked: {
                        if (root.modalitaRegistrazione)
                            loginVM.registrati(campoEmail.text.trim(), campoPassword.text, campoNome.text.trim(), "Master")
                        else
                            loginVM.accedi(campoEmail.text.trim(), campoPassword.text)
                    }
                }

                FMButton {
                    width: parent.width
                    text: root.modalitaRegistrazione ? "Hai gia' un account? Accedi" : "Registra un nuovo club"
                    onClicked: root.modalitaRegistrazione = !root.modalitaRegistrazione
                }
            }
        }

        FMButton {
            width: parent.width
            text: "Continua senza connessione"
            onClicked: loginVM.accessoOffline()
        }
    }

    // Nota: alla riuscita del login (loginVM.accessoRiuscito) e' main.py,
    // lato Python, a occuparsi di costruire i ViewModel della sessione e
    // caricare App.qml al posto di questa finestra — non serve reagire al
    // segnale qui in QML.
    Component.onCompleted: loginVM.tentaAccessoAutomatico()
}
