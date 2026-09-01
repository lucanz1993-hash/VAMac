import QtQuick
import Theme

// Crossfade via snapshot al cambio tema, per evitare lo "scatto" istantaneo
// di tutti i colori. Va istanziato UNA VOLTA in App.qml, sopra ogni altro
// contenuto (z alto), con target: la ApplicationWindow stessa.
Image {
    id: overlay

    property Item target: null

    anchors.fill: parent
    z: 1000
    visible: opacity > 0
    opacity: 0
    fillMode: Image.Stretch

    Behavior on opacity {
        NumberAnimation { duration: Theme.motion.reveal; easing.type: Theme.motion.easeStandard }
    }

    function play(idTema) {
        if (!overlay.target) {
            ThemeManager.setThemeById(idTema)
            return
        }
        overlay.target.grabToImage(function (result) {
            // Ordine importante: lo swap di tema deve avvenire SOLO dentro
            // questo callback, dopo che lo snapshot e' stato catturato.
            // grabToImage() e' asincrono: cambiare la palette prima che si
            // risolva catturerebbe i colori GIA' nuovi, vanificando il
            // crossfade (si vedrebbe comunque uno scatto).
            overlay.source = result.url
            overlay.opacity = 1
            ThemeManager.setThemeById(idTema)
            overlay.opacity = 0
        })
    }
}
