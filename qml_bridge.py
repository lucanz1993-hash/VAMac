"""Punto unico di creazione di QQmlApplicationEngine: sia la finestra
principale che la Coaching Board (motore QML separato, vedi
coaching_board_window.py quando verra' ricostruita) passano da qui, cosi'
ThemeManager e il percorso di import QML restano coerenti ovunque."""

import os
import sys

# Vincolo tecnico verificato in questo ambiente: lo stile nativo "Windows" di
# QtQuick.Controls non risolve il proprio plugin qui, e il fallimento e'
# silenzioso (il file QML che usa un ComboBox smette semplicemente di
# caricarsi). "Basic" e' lo stile che funziona in modo affidabile: va
# impostato PRIMA che qualunque file QML con controlli venga caricato, quindi
# qui, all'import di questo modulo, non dentro crea_motore_qml().
os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")

from PyQt6.QtQml import QQmlApplicationEngine

from theme_manager import ottieni_theme_manager


def get_resource_path(percorso_relativo):
    """Risolve un percorso relativo alla root del progetto, sia in esecuzione
    da sorgente sia da eseguibile congelato con PyInstaller (sys._MEIPASS)."""
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, percorso_relativo)


QML_DIR = get_resource_path("qml")


def crea_motore_qml():
    engine = QQmlApplicationEngine()
    engine.addImportPath(QML_DIR)
    engine.rootContext().setContextProperty("ThemeManager", ottieni_theme_manager())
    return engine
