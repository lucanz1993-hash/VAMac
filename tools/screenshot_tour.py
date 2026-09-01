"""Cattura uno screenshot per ogni schermata principale dell'app, lanciata
in modalita' offline (nessun server/credenziali necessari) con piattaforma
Qt offscreen (nessun display reale richiesto - usato dalla CI macOS).

Naviga chiamando direttamente gli slot dei ViewModel (navigazioneVM.vaiA,
vaiAProfilo) invece di simulare click del mouse: stesso identico codice QML
che gira a runtime, ma senza bisogno di un framework di UI automation.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from PyQt6.QtCore import QTimer, QUrl
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQuick import QQuickWindow  # noqa: F401 - senza questo import SIP wrappa le finestre QML come QWindow base, senza grabWindow()

import crea_db
from qml_bridge import crea_motore_qml, get_resource_path
from viewmodels.login_vm import LoginVM
from viewmodels.navigazione_vm import NavigazioneVM
from viewmodels.dashboard_vm import DashboardVM
from viewmodels.profilo_vm import ProfiloVM
from viewmodels.anagrafica_vm import AnagraficaVM
from viewmodels.presenze_vm import PresenzeVM
from viewmodels.statistiche_vm import StatisticheVM
from viewmodels.macrociclo_vm import MacrocicloVM
from viewmodels.sedute_vm import SeduteVM
from viewmodels.hub_board_vm import HubBoardVM
from viewmodels.coaching_board_vm import CoachingBoardVM
from viewmodels.formazione_vm import FormazioneVM
from viewmodels.ricerca_vm import RicercaVM

CARTELLA_OUTPUT = sys.argv[1] if len(sys.argv) > 1 else "screenshots"
RITARDO_TRANSIZIONE_MS = 500  # Theme.motion.transition e' 220ms: margine per animazione + rendering.

# (indice sezione o None per Profilo, nome file)
TAPPE = [
    (0, "01-dashboard"),
    (1, "02-macrociclo"),
    (2, "03-sedute"),
    (3, "04-anagrafica"),
    (4, "05-presenze"),
    (5, "06-statistiche"),
    (6, "07-lavagna"),
    ("profilo", "08-profilo"),
]

_sessione = {}
_finestra_corrente = {}


def _salva_screenshot(nome):
    finestra = _finestra_corrente.get("win")
    if finestra is None:
        print(f"[screenshot_tour] ATTENZIONE: nessuna finestra per '{nome}'")
        return
    os.makedirs(CARTELLA_OUTPUT, exist_ok=True)
    percorso = os.path.join(CARTELLA_OUTPUT, f"{nome}.png")
    immagine = finestra.grabWindow()
    ok = immagine.save(percorso)
    print(f"[screenshot_tour] {'OK' if ok else 'FALLITO'}: {percorso}")


def main():
    crea_db.crea_database()
    app = QGuiApplication(sys.argv)
    engine = crea_motore_qml()

    login_vm = LoginVM()
    engine.rootContext().setContextProperty("loginVM", login_vm)

    def avvia_app(dati_utente):
        for oggetto in list(engine.rootObjects()):
            oggetto.close()
            oggetto.deleteLater()

        navigazione_vm = NavigazioneVM()
        dashboard_vm = DashboardVM(dati_utente)
        profilo_vm = ProfiloVM(dati_utente)
        anagrafica_vm = AnagraficaVM(dati_utente)
        presenze_vm = PresenzeVM(dati_utente)
        statistiche_vm = StatisticheVM(dati_utente)
        macrociclo_vm = MacrocicloVM(dati_utente)
        sedute_vm = SeduteVM(dati_utente)
        hub_board_vm = HubBoardVM()
        coaching_board_vm = CoachingBoardVM()
        formazione_vm = FormazioneVM(dati_utente)
        ricerca_vm = RicercaVM(dati_utente)

        _sessione.update({
            "navigazioneVM": navigazione_vm, "dashboardVM": dashboard_vm, "profiloVM": profilo_vm,
            "anagraficaVM": anagrafica_vm, "presenzeVM": presenze_vm, "statisticheVM": statistiche_vm,
            "macrocicloVM": macrociclo_vm, "seduteVM": sedute_vm, "hubBoardVM": hub_board_vm,
            "coachingBoardVM": coaching_board_vm, "formazioneVM": formazione_vm, "ricercaVM": ricerca_vm,
        })
        for nome, vm in _sessione.items():
            engine.rootContext().setContextProperty(nome, vm)

        engine.load(QUrl.fromLocalFile(get_resource_path("qml/App.qml")))
        if not engine.rootObjects():
            print("[screenshot_tour] ERRORE: App.qml non caricato")
            app.exit(1)
            return
        _finestra_corrente["win"] = engine.rootObjects()[0]

        def avanza(indice_tappa):
            if indice_tappa >= len(TAPPE):
                app.quit()
                return
            sezione, nome_file = TAPPE[indice_tappa]
            if sezione == "profilo":
                navigazione_vm.vaiAProfilo()
            else:
                navigazione_vm.vaiA(sezione)
            QTimer.singleShot(RITARDO_TRANSIZIONE_MS, lambda: (
                _salva_screenshot(nome_file),
                avanza(indice_tappa + 1),
            ))

        # Prima tappa (Dashboard) e' gia' la vista iniziale: basta aspettare
        # il primo render prima di catturarla, poi si parte dalla seconda.
        QTimer.singleShot(RITARDO_TRANSIZIONE_MS, lambda: (
            _salva_screenshot(TAPPE[0][1]),
            avanza(1),
        ))

    login_vm.accessoRiuscito.connect(avvia_app)

    engine.load(QUrl.fromLocalFile(get_resource_path("qml/Login.qml")))
    if not engine.rootObjects():
        print("[screenshot_tour] ERRORE: Login.qml non caricato")
        sys.exit(1)
    _finestra_corrente["win"] = engine.rootObjects()[0]

    QTimer.singleShot(RITARDO_TRANSIZIONE_MS, lambda: (
        _salva_screenshot("00-login"),
        login_vm.accessoOffline(),
    ))

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
