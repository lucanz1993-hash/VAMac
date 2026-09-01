"""Gestione dei temi (skin) dell'interfaccia, sul modello delle skin di
Football Manager: stessa struttura/animazioni, solo la palette colori cambia.

Prima di questa sessione non esisteva alcuna persistenza delle preferenze
utente in questo progetto (nessun uso di QSettings da nessuna parte): questo
modulo introduce il pattern, non lo eredita da codice precedente.
"""

from PyQt6.QtCore import QObject, QSettings, pyqtProperty, pyqtSignal, pyqtSlot

ORGANIZZAZIONE = "LB Coaching"
APPLICAZIONE = "FC Manager"
CHIAVE_TEMA = "aspetto/tema_id"

# Ogni tema condivide typography/motion/elevation/spacing/radius (definiti in
# qml/Theme/Theme.qml): le skin FM cambiano colore, non geometria. Qui vive
# solo la parte che cambia da un tema all'altro.
#
# ATTENZIONE colori con alpha (es. accentSoft): usare SEMPRE la notazione
# esadecimale "#AARRGGBB", mai la sintassi CSS "rgba(r,g,b,a)". QColor/QML
# non la riconoscono come colore valido e ripiegano silenziosamente su nero
# opaco, senza alcun warning in console — bug reale scoperto solo guardando
# uno screenshot del tema Light Contrast (la voce di menu attiva nella Side
# Bar appariva nera invece che con una tinta oro trasparente).
PALETTE = [
    {
        "id": "fm_dark",
        "nome": "FM Dark",
        "colori": {
            "bgMain": "#12111a", "bgSurface": "#1a1826", "bgSurface2": "#242236", "bgSurface3": "#2f2c42",
            "accent": "#e0a94a", "accentHover": "#e8bb6a", "accentPressed": "#c8933a", "accentSoft": "#29e0a94a",
            "primario": "#3d5afe", "primarioHover": "#5c74ff", "primarioPressed": "#2c42d1",
            "terziario": "#a06bea",
            "textPrimary": "#ffffff", "textSecondary": "#a8a4b8", "textTertiary": "#6f6b80",
            "border": "#332f47", "borderStrong": "#4a4560",
            "positive": "#4fd17a", "negative": "#e0544f", "negativeHover": "#e97672", "neutral": "#d1a34f",
            "success": "#2ecc71", "successHover": "#27ae60", "danger": "#e74c3c", "dangerHover": "#c0392b",
            "warning": "#f1c40f", "warningHover": "#d4ac0d",
        },
    },
    {
        "id": "classic_navy",
        "nome": "Classic Navy",
        "colori": {
            "bgMain": "#0d1520", "bgSurface": "#14202e", "bgSurface2": "#1c2c3e", "bgSurface3": "#26394e",
            "accent": "#e0a94a", "accentHover": "#e8bb6a", "accentPressed": "#c8933a", "accentSoft": "#29e0a94a",
            "primario": "#2f8fe0", "primarioHover": "#55a6e8", "primarioPressed": "#1f6fb8",
            "terziario": "#9b6ee0",
            "textPrimary": "#f2f5f8", "textSecondary": "#93a3b8", "textTertiary": "#5f7186",
            "border": "#223345", "borderStrong": "#35526e",
            "positive": "#4fd18a", "negative": "#e0544f", "negativeHover": "#e97672", "neutral": "#d1a34f",
            "success": "#2ecc71", "successHover": "#27ae60", "danger": "#e74c3c", "dangerHover": "#c0392b",
            "warning": "#f1c40f", "warningHover": "#d4ac0d",
        },
    },
    {
        "id": "light_contrast",
        "nome": "Light Contrast",
        "colori": {
            "bgMain": "#f4f5f7", "bgSurface": "#ffffff", "bgSurface2": "#e9ebf0", "bgSurface3": "#dde1e8",
            "accent": "#b8791f", "accentHover": "#a3690f", "accentPressed": "#8c5a0d", "accentSoft": "#24b8791f",
            "primario": "#2f3fc0", "primarioHover": "#4451d1", "primarioPressed": "#232fa0",
            "terziario": "#6b3fa0",
            "textPrimary": "#14151b", "textSecondary": "#4d5566", "textTertiary": "#767e8f",
            "border": "#d7dbe2", "borderStrong": "#b7bfcc",
            "positive": "#1f9c52", "negative": "#c0392b", "negativeHover": "#a5301f", "neutral": "#96721f",
            "success": "#1f9c52", "successHover": "#178042", "danger": "#c0392b", "dangerHover": "#a5301f",
            "warning": "#a3790a", "warningHover": "#8a6608",
        },
    },
    {
        "id": "high_contrast",
        "nome": "Alto Contrasto",
        "colori": {
            "bgMain": "#000000", "bgSurface": "#0d0d0d", "bgSurface2": "#1a1a1a", "bgSurface3": "#262626",
            "accent": "#ffd400", "accentHover": "#ffe14d", "accentPressed": "#e0bb00", "accentSoft": "#2effd400",
            "primario": "#4da6ff", "primarioHover": "#70b8ff", "primarioPressed": "#2f8fe0",
            "terziario": "#c77dff",
            "textPrimary": "#ffffff", "textSecondary": "#e0e0e0", "textTertiary": "#b0b0b0",
            "border": "#3d3d3d", "borderStrong": "#666666",
            "positive": "#3ddc84", "negative": "#ff6b60", "negativeHover": "#ff8c83", "neutral": "#ffd400",
            "success": "#3ddc84", "successHover": "#2ec46e", "danger": "#ff6b60", "dangerHover": "#ff8c83",
            "warning": "#ffd400", "warningHover": "#ffe14d",
        },
    },
]

_INDICE_PER_ID = {p["id"]: i for i, p in enumerate(PALETTE)}


class ThemeManager(QObject):
    """Singleton di processo (non per-finestra): registrato come context
    property su OGNI QQmlApplicationEngine creato da qml_bridge.py, cosi' la
    finestra principale e la Coaching Board (motore QML separato) restano
    sempre sincronizzate sullo stesso tema."""

    paletteChanged = pyqtSignal()

    def __init__(self, parent=None):
        super().__init__(parent)
        settings = QSettings(ORGANIZZAZIONE, APPLICAZIONE)
        id_salvato = settings.value(CHIAVE_TEMA, PALETTE[0]["id"])
        self._indice = _INDICE_PER_ID.get(id_salvato, 0)

    @pyqtProperty("QVariantMap", notify=paletteChanged)
    def activePalette(self):
        return PALETTE[self._indice]["colori"]

    @pyqtProperty(int, notify=paletteChanged)
    def currentIndex(self):
        return self._indice

    @pyqtProperty("QVariantList", constant=True)
    def availableThemes(self):
        return [
            {
                "id": p["id"],
                "nome": p["nome"],
                "previewBg": p["colori"]["bgMain"],
                "previewSurface": p["colori"]["bgSurface2"],
                "previewAccent": p["colori"]["accent"],
            }
            for p in PALETTE
        ]

    @pyqtSlot(str)
    def setThemeById(self, id_tema):
        indice = _INDICE_PER_ID.get(id_tema)
        if indice is None or indice == self._indice:
            return
        self._indice = indice
        QSettings(ORGANIZZAZIONE, APPLICAZIONE).setValue(CHIAVE_TEMA, id_tema)
        self.paletteChanged.emit()


_istanza = None


def ottieni_theme_manager():
    global _istanza
    if _istanza is None:
        _istanza = ThemeManager()
    return _istanza
