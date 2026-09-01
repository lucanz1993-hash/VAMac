"""Punto di ingresso unico dell'applicazione (sostituisce sia il vecchio
menu_principale.py — shell QWidget — sia il precedente main_qml.py, che
girava "in parallelo" come prototipo: da questa sessione in poi la UI QML
non e' piu' un prototipo parallelo, e' l'unica applicazione).

Flusso: mostra qml/Login.qml; alla riuscita del login costruisce i
ViewModel della sessione autenticata e carica qml/App.qml al suo posto.
"""

import sys

from PyQt6.QtCore import QUrl
from PyQt6.QtGui import QGuiApplication

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

# Riferimenti tenuti vivi esplicitamente: senza questo dict, il garbage
# collector di Python potrebbe liberare i ViewModel non appena le funzioni
# che li creano ritornano, mentre QML ne detiene ancora solo un riferimento
# "debole" tramite il context property.
_sessione = {}


def _chiudi_finestre_correnti(engine):
    for oggetto in list(engine.rootObjects()):
        oggetto.close()
        oggetto.deleteLater()


def main():
    # FIX: nessun punto dell'avvio richiamava crea_db.crea_database() (il
    # vecchio menu_principale.py lo faceva, main.py no): su un'installazione
    # nuova senza gestione_squadra.db lo schema non veniva mai creato, e le
    # migrazioni idempotenti aggiunte nel tempo (_MIGRAZIONI_COLONNE) non si
    # applicavano mai automaticamente a un DB esistente piu' vecchio -
    # bisognava lanciare crea_db.py a mano. Idempotente, sicura ad ogni avvio.
    crea_db.crea_database()
    app = QGuiApplication(sys.argv)
    engine = crea_motore_qml()

    login_vm = LoginVM()
    engine.rootContext().setContextProperty("loginVM", login_vm)

    def torna_al_login():
        _chiudi_finestre_correnti(engine)
        _sessione.clear()
        engine.load(QUrl.fromLocalFile(get_resource_path("qml/Login.qml")))

    def avvia_app(dati_utente):
        _chiudi_finestre_correnti(engine)

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
        profilo_vm.logoutRichiesto.connect(torna_al_login)
        profilo_vm.accountEliminato.connect(torna_al_login)

        # Creare/eliminare un gruppo e' possibile SOLO dalla schermata
        # Macrociclo (centralizzato li', rimosso da Anagrafica): le altre
        # schermate restano sincronizzate collegando qui il suo segnale
        # gruppiCambiati ai ricaricaGruppi() degli altri VM, cosi' un
        # gruppo creato/eliminato si riflette ovunque senza dover riaprire
        # la schermata - il refresh su Component.onCompleted di ciascuna
        # schermata resta comunque come rete di sicurezza.
        macrociclo_vm.gruppiCambiati.connect(anagrafica_vm.ricaricaGruppi)
        macrociclo_vm.gruppiCambiati.connect(sedute_vm.ricaricaGruppi)
        macrociclo_vm.gruppiCambiati.connect(presenze_vm.ricaricaGruppi)
        macrociclo_vm.gruppiCambiati.connect(statistiche_vm.ricaricaGruppi)

        _sessione["navigazioneVM"] = navigazione_vm
        _sessione["dashboardVM"] = dashboard_vm
        _sessione["profiloVM"] = profilo_vm
        _sessione["anagraficaVM"] = anagrafica_vm
        _sessione["presenzeVM"] = presenze_vm
        _sessione["statisticheVM"] = statistiche_vm
        _sessione["macrocicloVM"] = macrociclo_vm
        _sessione["seduteVM"] = sedute_vm
        _sessione["hubBoardVM"] = hub_board_vm
        _sessione["coachingBoardVM"] = coaching_board_vm
        _sessione["formazioneVM"] = formazione_vm
        _sessione["ricercaVM"] = ricerca_vm

        engine.rootContext().setContextProperty("navigazioneVM", navigazione_vm)
        engine.rootContext().setContextProperty("dashboardVM", dashboard_vm)
        engine.rootContext().setContextProperty("profiloVM", profilo_vm)
        engine.rootContext().setContextProperty("anagraficaVM", anagrafica_vm)
        engine.rootContext().setContextProperty("presenzeVM", presenze_vm)
        engine.rootContext().setContextProperty("statisticheVM", statistiche_vm)
        engine.rootContext().setContextProperty("macrocicloVM", macrociclo_vm)
        engine.rootContext().setContextProperty("seduteVM", sedute_vm)
        engine.rootContext().setContextProperty("hubBoardVM", hub_board_vm)
        engine.rootContext().setContextProperty("coachingBoardVM", coaching_board_vm)
        engine.rootContext().setContextProperty("formazioneVM", formazione_vm)
        engine.rootContext().setContextProperty("ricercaVM", ricerca_vm)

        engine.load(QUrl.fromLocalFile(get_resource_path("qml/App.qml")))
        if not engine.rootObjects():
            sys.exit(-1)

    login_vm.accessoRiuscito.connect(avvia_app)

    engine.load(QUrl.fromLocalFile(get_resource_path("qml/Login.qml")))
    if not engine.rootObjects():
        sys.exit(-1)

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
