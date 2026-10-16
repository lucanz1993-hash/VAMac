import sqlite3
import requests
import os
import sys
from datetime import date, timedelta

# --- FIX PERCORSO ASSOLUTO UNIVERSALE PER EXE E PYTHON ---
if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

DB_LOCALE = os.path.join(BASE_DIR, 'gestione_squadra.db')
INDIRIZZO_SERVER = "http://127.0.0.1:8000"

GIORNI = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom']


def _data_cella_macrociclo(stagione, id_settimana, giorno):
    """Ricalcola la data effettiva (date) di una cella lun..dom del
    macrociclo a partire da stagione ("2026/2027"), numero di settimana
    (1..53) e nome del giorno, con ESATTAMENTE la stessa formula usata per
    disegnare la griglia in interfaccia_macrociclo.py
    (FinestraMacrociclo.ricalcola_date_calendario): la stagione inizia dal
    lunedì della settimana che contiene il 1° luglio dell'anno iniziale, e
    ogni settimana successiva aggiunge 7 giorni. Necessario per poter
    stabilire la data di una cella compilata (A/TM/TA/C) anche quando non
    ha ancora nessuna seduta collegata (nessuna riga in "sedute" da cui
    leggere una data reale). Restituisce None se stagione/settimana non
    sono in un formato valido, invece di far fallire l'intera dashboard."""
    try:
        anno_inizio = int(stagione.split("/")[0])
        luglio_1 = date(anno_inizio, 7, 1)
        # isoweekday(): lunedì=1 ... domenica=7, stesso schema di
        # QDate.dayOfWeek() usato lato client.
        inizio_lunedi = luglio_1 - timedelta(days=luglio_1.isoweekday() - 1)
        offset_giorno = GIORNI.index(giorno)
        return inizio_lunedi + timedelta(days=(int(id_settimana) - 1) * 7 + offset_giorno)
    except (ValueError, TypeError, IndexError):
        return None


def _id_settimana_giorno_da_data(stagione, data_str):
    """Inversa di _data_cella_macrociclo: da una data reale (usata dal
    Calendario & Eventi di Presenze) risale a quale cella lun..dom del
    macrociclo la contiene, per poter creare/collegare un evento cliccando
    direttamente su un giorno del mese invece di passare dal Macrociclo.
    Restituisce None se la data cade prima dell'inizio stagione o il
    formato non e' valido."""
    try:
        anno_inizio = int(stagione.split("/")[0])
        luglio_1 = date(anno_inizio, 7, 1)
        inizio_lunedi = luglio_1 - timedelta(days=luglio_1.isoweekday() - 1)
        d = date.fromisoformat(data_str)
        delta_giorni = (d - inizio_lunedi).days
        if delta_giorni < 0:
            return None
        return (delta_giorni // 7) + 1, GIORNI[delta_giorni % 7]
    except (ValueError, TypeError, IndexError):
        return None


def _periodo_predefinito_settimana(stagione, id_settimana):
    """Testo di default per il campo "periodo" di una settimana: l'intervallo
    di date reale lun-dom (stessa ancora di _data_cella_macrociclo), cosi'
    una settimana appena creata mostra subito QUANDO cade invece di restare
    vuota in attesa che l'utente scriva una descrizione a mano - che resta
    comunque modificabile in qualunque momento (es. "Pre-campionato")."""
    inizio = _data_cella_macrociclo(stagione, id_settimana, "lun")
    fine = _data_cella_macrociclo(stagione, id_settimana, "dom")
    if not inizio or not fine:
        return ""
    return f"{inizio.strftime('%d-%m-%Y')} - {fine.strftime('%d-%m-%Y')}"


def calcola_numero_settimane_stagione(stagione):
    """Numero di settimane della stagione (52 o 53), calcolato con la STESSA
    ancora di _data_cella_macrociclo (lunedì della settimana che contiene il
    1° luglio): la stagione "YYYY/YYYY+1" copre dal lunedì di inizio-luglio
    dell'anno di partenza al lunedì di inizio-luglio dell'anno successivo.
    Usata per generare automaticamente tutte le settimane alla creazione di
    un nuovo gruppo (vedi DataManager.crea_gruppo_con_settimane). Ritorna 52
    come fallback se la stagione non è nel formato atteso, invece di far
    fallire la creazione del gruppo."""
    try:
        anno_inizio = int(stagione.split("/")[0])
    except (ValueError, TypeError, IndexError):
        return 52

    def _lunedi_luglio(anno):
        luglio_1 = date(anno, 7, 1)
        return luglio_1 - timedelta(days=luglio_1.isoweekday() - 1)

    return (_lunedi_luglio(anno_inizio + 1) - _lunedi_luglio(anno_inizio)).days // 7


def _connetti_locale():
    """Apre una connessione al DB locale con l'enforcement delle foreign key
    ATTIVO. SQLite disattiva PRAGMA foreign_keys per ogni nuova connessione a
    meno che non lo si riattivi esplicitamente: usare sempre questa funzione
    al posto di sqlite3.connect(DB_LOCALE) diretto, altrimenti i vincoli
    ON DELETE CASCADE definiti in crea_db.py non scattano mai (bug storico:
    cancellare un giocatore lasciava le sue presenze orfane per sempre)."""
    conn = sqlite3.connect(DB_LOCALE)
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def _risolvi_societa_locale(cursor, nome_societa, id_creatore="locale_admin"):
    """Equivalente offline di risolvi_societa() lato server: dato un nome di
    club scritto liberamente, restituisce (id_societa, nome_canonico) usando
    cartelle_societa (già esistente per i permessi) come registro univoco.

    Il confronto è case-insensitive e ignora gli spazi ai bordi: prima di
    questa funzione, i vari punti del codice che facevano
    "INSERT OR IGNORE INTO cartelle_societa (nome, ...)" con il nome grezzo
    si affidavano al vincolo UNIQUE di SQLite, che però è sensibile a
    maiuscole/minuscole — "ASD Test" e "asd test" passavano entrambi come
    righe distinte, il "club fantasma" segnalato nell'audit. Restituire
    sempre lo stesso nome_canonico già salvato in precedenza e riscriverlo
    nelle colonne stringa elimina il problema alla radice.
    Nessuna società (spazio personale) => (None, "")."""
    nome_pulito = (nome_societa or "").strip()
    if not nome_pulito:
        return None, ""
    cursor.execute("SELECT id_societa, nome FROM cartelle_societa WHERE LOWER(TRIM(nome)) = LOWER(?)", (nome_pulito,))
    riga = cursor.fetchone()
    if riga:
        return riga[0], riga[1]
    cursor.execute(
        "INSERT INTO cartelle_societa (nome, id_creatore, is_personale) VALUES (?, ?, 0)",
        (nome_pulito, id_creatore),
    )
    return cursor.lastrowid, nome_pulito


def _filtro_societa_esatto(soc):
    """Filtro SQL per un'azione MIRATA (cancellazione/spostamento) su UNA
    specifica società o sui dati indipendenti, da usare al posto del filtro
    "(societa=? OR societa IS NULL OR societa='')" usato nelle letture
    aggregate.

    FIX: quel filtro, se riusato anche per cancellare/spostare, faceva sì che
    un'azione sul gruppo di un club specifico colpisse ANCHE le righe
    indipendenti (senza club) con la stessa categoria+stagione, cancellando o
    spostando per errore dati che non appartengono a nessun club - perdita
    dati silenziosa, senza alcun avviso. Restituisce (condizione_sql,
    parametro_o_None): se soc è valorizzato, la condizione è un confronto
    esatto e va aggiunto un placeholder; se soc è vuoto, la condizione
    seleziona solo le righe indipendenti e non richiede placeholder."""
    if soc:
        return "societa = ?", soc
    return "(societa IS NULL OR societa = '')", None


def _headers(dati_utente):
    """Header di autenticazione da allegare a ogni chiamata HTTP verso il
    server cloud. In precedenza nessuna chiamata trasportava alcuna prova di
    identità: il server si fidava di un id_richiedente passato liberamente
    nel payload. Ora ogni richiesta autenticata porta il token di sessione
    rilasciato al login."""
    token = (dati_utente or {}).get("token")
    return {"Authorization": f"Bearer {token}"} if token else {}


class DataManager:
    """Gestore centralizzato per le chiamate API Cloud e le query al DB Locale SQLite."""

    @staticmethod
    def _esegui_migrazione_sicura_cartelle(dati_utente):
        """
        Crea le nuove tabelle per la gestione a Cartelle (stile Google Drive)
        e migra i vecchi dati senza perdere nulla.
        """
        is_offline = dati_utente.get("offline", False)
        if not is_offline:
            return

        mio_id = dati_utente.get("id_utente", "locale_admin")

        try:
            conn = _connetti_locale()
            cursor = conn.cursor()

            # 1. Creazione delle nuove tabelle
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS cartelle_societa (
                    id_societa INTEGER PRIMARY KEY AUTOINCREMENT,
                    nome TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    id_creatore TEXT NOT NULL,
                    is_personale INTEGER DEFAULT 0
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS cartelle_categorie (
                    id_categoria INTEGER PRIMARY KEY AUTOINCREMENT,
                    id_societa INTEGER NOT NULL,
                    nome TEXT NOT NULL,
                    id_creatore TEXT NOT NULL,
                    FOREIGN KEY(id_societa) REFERENCES cartelle_societa(id_societa) ON DELETE CASCADE
                )
            """)
            cursor.execute("""
                CREATE TABLE IF NOT EXISTS permessi_cartelle (
                    id_permesso INTEGER PRIMARY KEY AUTOINCREMENT,
                    id_societa INTEGER,
                    id_categoria INTEGER,
                    id_utente TEXT NOT NULL,
                    ruolo TEXT NOT NULL,
                    FOREIGN KEY(id_societa) REFERENCES cartelle_societa(id_societa) ON DELETE CASCADE,
                    FOREIGN KEY(id_categoria) REFERENCES cartelle_categorie(id_categoria) ON DELETE CASCADE
                )
            """)

            # 2. Migrazione se necessaria
            cursor.execute("SELECT COUNT(*) FROM cartelle_societa")
            if cursor.fetchone()[0] == 0:
                cursor.execute("""
                    SELECT DISTINCT societa FROM macrociclo WHERE societa IS NOT NULL AND societa != ''
                    UNION SELECT DISTINCT societa FROM giocatori WHERE societa IS NOT NULL AND societa != ''
                    UNION SELECT DISTINCT societa FROM sedute WHERE societa IS NOT NULL AND societa != ''
                """)
                vecchie_soc = [row[0] for row in cursor.fetchall()]

                for soc in vecchie_soc:
                    # FIX: la precedente INSERT OR IGNORE + SELECT nome=?
                    # (confronto esatto) creava una riga cartelle_societa
                    # distinta per ogni variazione di maiuscole/spazi dello
                    # stesso nome già presente nei dati storici. Il resolver
                    # comune, case-insensitive, evita di seminare da subito
                    # dei "club fantasma" duplicati in questa migrazione.
                    id_soc, _ = _risolvi_societa_locale(cursor, soc, mio_id)
                    if id_soc is not None:
                        cursor.execute("INSERT INTO permessi_cartelle (id_societa, id_utente, ruolo) VALUES (?, ?, 'Master')", (id_soc, mio_id))

                cursor.execute("""
                    SELECT DISTINCT categoria, societa FROM macrociclo
                    UNION SELECT DISTINCT categoria, societa FROM giocatori
                    UNION SELECT DISTINCT categoria, societa FROM sedute
                """)
                vecchie_cat = cursor.fetchall()

                for cat, soc in vecchie_cat:
                    soc_nome = soc if soc else ""
                    if soc_nome:
                        cursor.execute("SELECT id_societa FROM cartelle_societa WHERE LOWER(TRIM(nome)) = LOWER(?)", (soc_nome,))
                        res_soc = cursor.fetchone()
                        if res_soc:
                            id_soc = res_soc[0]
                            cursor.execute("INSERT INTO cartelle_categorie (id_societa, nome, id_creatore) VALUES (?, ?, ?)", (id_soc, cat, mio_id))

            # 3. Backfill id_societa: collega ogni riga con "societa" non
            # vuota ma id_societa ancora NULL al club canonico corrispondente
            # in cartelle_societa, e RISCRIVE anche la stringa. Questo ripara
            # retroattivamente i "club fantasma" già presenti nel DB locale
            # (nati da spazi/maiuscole diverse tra un salvataggio e l'altro
            # dello stesso nome), oltre a preparare il terreno per usare
            # l'id numerico invece della stringa. Idempotente: una volta che
            # tutte le righe hanno un id_societa non fa più nulla.
            for tabella in ("giocatori", "sedute", "macrociclo"):
                cursor.execute(
                    f"SELECT rowid, societa FROM {tabella} WHERE id_societa IS NULL AND societa IS NOT NULL AND societa != ''"
                )
                da_aggiornare = cursor.fetchall()
                for rowid, nome_soc in da_aggiornare:
                    id_soc, nome_canonico = _risolvi_societa_locale(cursor, nome_soc, mio_id)
                    cursor.execute(f"UPDATE {tabella} SET societa=?, id_societa=? WHERE rowid=?", (nome_canonico, id_soc, rowid))

            # 4. Pulizia sedute "fantasma" agganciate al macrociclo: prima di
            # questa correzione, cambiare manualmente il tipo di una cella
            # del macrociclo (es. da "TM"/"A" a vuoto) senza usare "Scollega"/
            # "Elimina" lasciava id_seduta_<giorno> intatto anche con la
            # cella svuotata. La seduta collegata restava quindi invisibile
            # in questa griglia ma ancora presente con la sua data, il che
            # falsava qualunque calcolo basato sulla data ovunque nell'app
            # scansioni direttamente la tabella "sedute" (es. la "prossima
            # seduta" mostrata in Dashboard), perché quel controllo non passa
            # dal macrociclo e non può sapere che la cella è stata svuotata.
            # Le sedute di tipo "Partita" esistono solo per essere agganciate
            # a una cella TM/TA/C: una volta orfane non hanno alcun altro uso,
            # quindi vengono eliminate del tutto (non solo scollegate).
            # Le sedute "normali" (Allenamento, numerate) possono invece avere
            # contenuto utile (esercitazioni, presenze): vengono solo
            # scollegate, mai cancellate qui. Idempotente.
            for gg in ("lun", "mar", "mer", "gio", "ven", "sab", "dom"):
                cursor.execute(
                    f"SELECT id_seduta_{gg} FROM macrociclo "
                    f"WHERE TRIM(COALESCE({gg}, ''))='' AND id_seduta_{gg} IS NOT NULL"
                )
                id_orfani = [row[0] for row in cursor.fetchall()]
                for id_s in id_orfani:
                    cursor.execute("SELECT numero_seduta FROM sedute WHERE id_seduta=?", (id_s,))
                    riga_s = cursor.fetchone()
                    if riga_s and riga_s[0] == "Partita":
                        cursor.execute("SELECT id_esercitazione FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                        for es in cursor.fetchall():
                            cursor.execute("DELETE FROM esercitazioni WHERE id_esercitazione=?", (es[0],))
                        cursor.execute("DELETE FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                        cursor.execute("DELETE FROM presenze WHERE id_seduta=?", (id_s,))
                        cursor.execute("DELETE FROM sedute WHERE id_seduta=?", (id_s,))
                cursor.execute(
                    # FIX: mancava di azzerare anche nota_<giorno> (la "Board
                    # Partita": avversario, luogo, risultato...). Restava
                    # salvata sulla riga di macrociclo e ricompariva pari
                    # pari se in seguito si creava una nuova seduta sulla
                    # stessa cella (stessa settimana/giorno), facendo
                    # sembrare che i dati della vecchia partita fantasma non
                    # fossero mai stati davvero ripuliti.
                    f"UPDATE macrociclo SET id_seduta_{gg}=NULL, nota_{gg}='' "
                    f"WHERE TRIM(COALESCE({gg}, ''))='' AND id_seduta_{gg} IS NOT NULL"
                )

            # 4bis. RIMOSSA. Faceva una spazzata più ampia: cancellava
            # qualunque seduta "Partita" non referenziata da NESSUNA cella
            # di NESSUNA settimana, per ripulire i residui di una vecchia
            # versione del fix che si limitava a scollegare senza
            # eliminare. Si è rivelata pericolosa: una cella TM/TA/C può
            # perdere il proprio id_seduta_<giorno> per varie cause (non
            # tutte identificate) pur restando visivamente "TM" nella
            # griglia, e questa spazzata cancellava allora la seduta reale
            # sottostante - è esattamente quello che è successo a due
            # partite realmente programmate, sparite dalla Dashboard senza
            # che l'utente avesse mai chiesto di eliminarle. Una cella
            # rimasta "TM" senza seduta collegata ora resta semplicemente
            # tale (recuperabile riaprendo "📝 Presenze" su quella cella,
            # che ricrea e riaggancia una seduta) invece di far sparire per
            # sempre dati che l'utente non ha mai scelto di cancellare.

            # 4ter. Rete di sicurezza finale: qualunque cella ormai senza
            # tipo e senza seduta collegata (id_seduta_<giorno> NULL) ma con
            # ancora una nota_<giorno> non vuota è per definizione una nota
            # residua di una vecchia "Board Partita" mai ripulita del tutto
            # (es. da versioni precedenti di questa migrazione, prima che
            # azzerassero anche la nota). Senza tipo né seduta collegata la
            # nota non ha alcun significato: la azzeriamo.
            for gg in ("lun", "mar", "mer", "gio", "ven", "sab", "dom"):
                cursor.execute(
                    f"UPDATE macrociclo SET nota_{gg}='' "
                    f"WHERE TRIM(COALESCE({gg}, ''))='' AND id_seduta_{gg} IS NULL "
                    f"AND COALESCE(nota_{gg}, '') != ''"
                )

            # 5. Aggiornamento delle liste standard di Obiettivo Tecnico,
            # Obiettivo Tattico e Obiettivo Condizionale/Coordinativo
            # (categorie 'Tecnici'/'Tattici'/'Condizionali' in
            # menu_tendine, condivise da Macrociclo e Interfaccia Seduta).
            # Le vecchie voci di default vengono rimosse SOLO se coincidono
            # esattamente con un valore delle vecchie liste (mai toccate
            # eventuali voci personalizzate aggiunte a mano dall'utente),
            # poi vengono inserite le nuove voci mancanti. Idempotente:
            # rieseguirla non fa nulla se le liste sono già aggiornate.
            RIMOSSE_TECNICI = ("Trasmissione", "Ricezione", "Rimessa laterale", "Smarcamento", "Marcamento", "Intercetto", "Difesa 1 vs 1")
            NUOVI_TECNICI = ("Conduzione", "Finte", "Tiro in porta", "Trasmissione/Ricezione", "Colpo di testa", "Contrasto")
            RIMOSSE_TATTICI = ("Scelta con palla", "Scelta senza palla", "Percezione dell'intorno", "Lettura duello con palla",
                                "Lettura duello senza palla", "Lettura 2 vs 2", "Lettura 3 vs 3", "Lettura superiorità numerica",
                                "Lettura inferiorità numerica", "Transizioni positive", "Transizioni negative", "Finalizzazione",
                                "Percezione intorno", "Lettura inferiorità", "Lettura superiorità", "Utilizzo dello spazio")
            NUOVI_TATTICI = ("Smarcamento", "Scelte offensive", "Scelte difensive", "Superiorità/Inferiorità numerica", "Marcamento")
            RIMOSSE_CONDIZIONALI = ("Coordinativo",)
            NUOVI_CONDIZIONALI = ("Velocità", "Forza", "Resistenza", "Ritmo", "Frequenza", "Differenziazione", "Reazione")

            for categoria, rimosse, nuove in (
                ("Tecnici", RIMOSSE_TECNICI, NUOVI_TECNICI),
                ("Tattici", RIMOSSE_TATTICI, NUOVI_TATTICI),
                ("Condizionali", RIMOSSE_CONDIZIONALI, NUOVI_CONDIZIONALI),
            ):
                for v in rimosse:
                    cursor.execute("DELETE FROM menu_tendine WHERE categoria=? AND valore=?", (categoria, v))
                cursor.execute("SELECT valore FROM menu_tendine WHERE categoria=?", (categoria,))
                esistenti = {r[0] for r in cursor.fetchall()}
                for v in nuove:
                    if v not in esistenti:
                        cursor.execute("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", (categoria, v))

            conn.commit()
            conn.close()
        except Exception as e:
            print(f"Errore durante la migrazione sicura: {e}")

    # ==========================================
    # MODULO: NUOVO SISTEMA PERMESSI CARTELLE
    # ==========================================
    @staticmethod
    def ha_permesso_cartella(dati_utente, soc_nome, cat_nome=""):
        """Verifica se l'utente ha accesso a una società/categoria.

        FIX: la versione precedente, per gli utenti "online" (cloud) non
        amministratori, richiamava ha_permesso(...) che a sua volta richiamava
        di nuovo ha_permesso_cartella(...) con gli stessi argomenti: una
        ricorsione infinita garantita (RecursionError) per qualunque utente
        cloud non-admin con una società assegnata. Ora il ramo online calcola
        direttamente il permesso dai dati di sessione (nome_societa/ruolo/
        categorie restituiti dal login), senza alcuna chiamata circolare.
        Il controllo qui è comunque solo un filtro per l'interfaccia: è il
        server (vedi verifica_permesso_dati in main.py) a fare da vera barriera
        di sicurezza per la modalità cloud.
        """
        DataManager._esegui_migrazione_sicura_cartelle(dati_utente)
        if DataManager.is_admin(dati_utente): return True
        if not soc_nome: return True

        is_offline = dati_utente.get("offline", False)
        mio_id = dati_utente.get("id_utente", "locale_admin")

        if is_offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                # FIX: confronto esatto (s.nome = ?) su quella che è la vera
                # barriera di sicurezza in modalità offline, mentre il resto
                # del file (_risolvi_societa_locale ed elimina_societa_completa)
                # usa già LOWER(TRIM(nome)) = LOWER(?) per evitare i "club
                # fantasma" da differenze di maiuscole/spazi. Lasciato
                # com'era, un soc_nome che differisce anche solo per
                # maiuscole/spazi dal nome canonico salvato negava un accesso
                # legittimo. Allineato allo stesso pattern case-insensitive.
                cursor.execute("""
                    SELECT p.ruolo FROM permessi_cartelle p
                    JOIN cartelle_societa s ON p.id_societa = s.id_societa
                    WHERE LOWER(TRIM(s.nome)) = LOWER(TRIM(?)) AND p.id_utente = ?
                """, (soc_nome, mio_id))
                res = cursor.fetchone()
                if res:
                    conn.close()
                    return True

                if cat_nome:
                    cursor.execute("""
                        SELECT p.ruolo FROM permessi_cartelle p
                        JOIN cartelle_categorie c ON p.id_categoria = c.id_categoria
                        JOIN cartelle_societa s ON c.id_societa = s.id_societa
                        WHERE LOWER(TRIM(s.nome)) = LOWER(TRIM(?)) AND c.nome = ? AND p.id_utente = ?
                    """, (soc_nome, cat_nome, mio_id))
                    res_cat = cursor.fetchone()
                    conn.close()
                    return bool(res_cat)

                conn.close()
                return False
            except Exception as e:
                print(f"Errore controllo permesso cartella: {e}")
                return False
        else:
            soc_utente = (dati_utente.get("nome_societa") or "").strip()
            if (soc_nome or "").strip() != soc_utente:
                return False
            if dati_utente.get("ruolo") == "Master":
                return True
            categorie = dati_utente.get("categorie", []) or []
            return (not cat_nome) or (cat_nome in categorie)

    @staticmethod
    def get_utenti_cartella(dati_utente, soc_nome):
        is_offline = dati_utente.get("offline", False)
        utenti = []
        if is_offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                cursor.execute("""
                    SELECT p.id_utente, p.ruolo
                    FROM permessi_cartelle p
                    JOIN cartelle_societa s ON p.id_societa = s.id_societa
                    WHERE LOWER(TRIM(s.nome)) = LOWER(TRIM(?))
                """, (soc_nome,))

                for row in cursor.fetchall():
                    utenti.append({"email": row[0], "ruolo": row[1]})
                conn.close()
            except Exception as e:
                print(f"Errore recupero utenti cartella: {e}")
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/utenti", headers=_headers(dati_utente), timeout=5)
                if r.status_code == 200:
                    for u in r.json():
                        if (u.get("nome_societa") or "").strip() == (soc_nome or "").strip():
                            utenti.append({"email": u.get("email"), "ruolo": u.get("ruolo")})
            except Exception as e:
                print(f"Errore recupero utenti cartella (cloud): {e}")
        return utenti

    @staticmethod
    def aggiungi_permesso_cartella(dati_utente, soc_nome, email_invitato, ruolo="User"):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                cursor.execute("SELECT id_societa FROM cartelle_societa WHERE LOWER(TRIM(nome)) = LOWER(TRIM(?))", (soc_nome,))
                res = cursor.fetchone()
                if not res:
                    conn.close()
                    raise Exception("Società non trovata nel DB.")

                id_soc = res[0]
                cursor.execute("""
                    INSERT INTO permessi_cartelle (id_societa, id_utente, ruolo)
                    SELECT ?, ?, ? WHERE NOT EXISTS (
                        SELECT 1 FROM permessi_cartelle WHERE id_societa=? AND id_utente=?
                    )
                """, (id_soc, email_invitato, ruolo, id_soc, email_invitato))
                conn.commit()
                conn.close()
            except Exception as e:
                raise Exception(f"Impossibile aggiungere utente: {e}")
        else:
            try:
                r = requests.post(f"{INDIRIZZO_SERVER}/utenti/invita", json={"email_invitato": email_invitato}, headers=_headers(dati_utente), timeout=5)
                if r.status_code != 200:
                    raise Exception(r.json().get("detail", "Invito fallito sul Cloud."))
            except requests.RequestException as e:
                raise Exception(f"Impossibile contattare il server: {e}")

    @staticmethod
    def rimuovi_permesso_cartella(dati_utente, soc_nome, email_da_rimuovere):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                cursor.execute("SELECT id_societa FROM cartelle_societa WHERE LOWER(TRIM(nome)) = LOWER(TRIM(?))", (soc_nome,))
                res = cursor.fetchone()
                if res:
                    id_soc = res[0]
                    cursor.execute("DELETE FROM permessi_cartelle WHERE id_societa=? AND id_utente=?", (id_soc, email_da_rimuovere))
                    conn.commit()
                conn.close()
            except Exception as e:
                raise Exception(f"Impossibile rimuovere utente: {e}")
        else:
            # FIX: in precedenza mancava del tutto il ramo online; la chiamata
            # non faceva letteralmente nulla, senza nemmeno un errore.
            try:
                r_utenti = requests.get(f"{INDIRIZZO_SERVER}/utenti", headers=_headers(dati_utente), timeout=5)
                id_target = None
                if r_utenti.status_code == 200:
                    for u in r_utenti.json():
                        if (u.get("email") or "").strip().lower() == email_da_rimuovere.strip().lower():
                            id_target = u.get("id_utente")
                            break
                if id_target is None:
                    raise Exception("Utente non trovato sul Cloud.")
                r = requests.post(f"{INDIRIZZO_SERVER}/utenti/{id_target}/rimuovi", headers=_headers(dati_utente), timeout=5)
                if r.status_code != 200:
                    raise Exception(r.json().get("detail", "Rimozione fallita sul Cloud."))
            except requests.RequestException as e:
                raise Exception(f"Impossibile contattare il server: {e}")

    @staticmethod
    def _assicura_permesso_scrittura(dati_utente, soc, cat_nome=""):
        """Gate di scrittura offline, usato da tutte le funzioni mutanti.

        FIX: aggiungere un controllo "secco" (if not ha_permesso_cartella:
        raise) a ogni funzione mutante - il gap principale segnalato
        nell'audit - avrebbe rotto la creazione stessa di un club nuovo:
        nessuno ha un permesso su una società che non esiste ancora, quindi
        anche il suo stesso creatore verrebbe bloccato. Il pattern già
        presente in salva_macrociclo_batch/sposta_gruppo_dati per il primo
        salvataggio su un club nuovo lo risolveva così: un INSERT automatico
        di un permesso 'Master' per l'utente corrente. Ma quel controllo era
        "WHERE NOT EXISTS (id_societa=? AND id_utente=?)" - cioè "questo
        utente non ha ancora un permesso su questo club" - non "nessuno ha
        ancora un permesso su questo club": significava che QUALUNQUE utente
        offline poteva auto-assegnarsi Master su un club ALTRUI già
        esistente, di proprietà di qualcun altro, semplicemente salvando un
        macrociclo con quel nome. Qui il controllo corretto è "nessuna riga
        in permessi_cartelle per questo id_societa, da NESSUN utente": solo
        allora il club è realmente "non reclamato" e il chiamante attuale ne
        diventa Master; altrimenti si nega l'accesso come per qualunque
        altro controllo permessi. Non fa nulla se l'accesso è già presente o
        non applicabile (dati indipendenti, modalità cloud, admin);
        solleva un'eccezione se l'accesso è negato."""
        if DataManager.ha_permesso_cartella(dati_utente, soc, cat_nome):
            return
        if not soc:
            return
        if not dati_utente.get("offline", False):
            return

        mio_id = dati_utente.get("id_utente", "locale_admin")
        conn = _connetti_locale()
        try:
            cursor = conn.cursor()
            id_soc, _ = _risolvi_societa_locale(cursor, soc, mio_id)
            if id_soc is not None:
                cursor.execute("SELECT 1 FROM permessi_cartelle WHERE id_societa=? LIMIT 1", (id_soc,))
                if cursor.fetchone() is None:
                    cursor.execute("INSERT INTO permessi_cartelle (id_societa, id_utente, ruolo) VALUES (?, ?, 'Master')", (id_soc, mio_id))
                    conn.commit()
                    return
        finally:
            conn.close()
        raise Exception(f"Non hai i permessi per modificare i dati di '{soc}'.")

    @staticmethod
    def is_admin(dati_utente):
        return dati_utente.get("ruolo") == "Admin"

    @staticmethod
    def ha_permesso(dati_utente, cat, soc_record):
        return DataManager.ha_permesso_cartella(dati_utente, soc_record, cat)

    # ==========================================
    # MODULO: GESTIONE SOCIETÀ (eliminazione/spostamento)
    # ==========================================
    @staticmethod
    def elimina_societa_completa(dati_utente, soc_nome):
        """Elimina in modo completo tutti i dati (macrocicli, sedute, fasi,
        esercitazioni, presenze, giocatori) di una società.

        FIX: in precedenza interfaccia_macrociclo.py implementava questa
        cancellazione SOLO per la modalità offline; in modalità cloud
        l'utente confermava un dialog che parlava di "eliminazione totale" e
        non succedeva assolutamente nulla, senza alcun errore visibile.
        """
        soc = (soc_nome or "").strip()
        if not soc:
            raise Exception("Nome società mancante.")
        is_offline = dati_utente.get("offline", False)

        # FIX: nessuna funzione di scrittura/cancellazione in questo file
        # controllava i permessi (ha_permesso_cartella veniva chiamata SOLO
        # dalle funzioni di elenco/lettura, mai da quelle mutanti): in
        # modalità offline un utente "User" poteva cancellare per intero i
        # dati di un club a cui non aveva accesso semplicemente chiamando
        # questa funzione. La modalità cloud resta protetta dal server (vedi
        # docstring di ha_permesso_cartella), quindi qui basta il controllo
        # lato offline.
        if is_offline:
            DataManager._assicura_permesso_scrittura(dati_utente, soc)

        if is_offline:
            conn = _connetti_locale()
            cursor = conn.cursor()
            try:
                # Risolviamo (senza crearla) l'id canonica del club: filtrare
                # anche per id_societa, oltre che per la stringa esatta,
                # evita che l'eliminazione totale sbagli bersaglio per un
                # refuso di spazi/maiuscole nel nome passato dall'interfaccia.
                cursor.execute("SELECT id_societa FROM cartelle_societa WHERE LOWER(TRIM(nome)) = LOWER(?)", (soc,))
                res_soc = cursor.fetchone()
                id_soc = res_soc[0] if res_soc else -1

                cursor.execute("SELECT id_seduta FROM sedute WHERE societa=? OR id_societa=?", (soc, id_soc))
                id_sedute = [r[0] for r in cursor.fetchall()]
                for id_s in id_sedute:
                    cursor.execute("SELECT id_esercitazione FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                    for es in cursor.fetchall():
                        cursor.execute("DELETE FROM esercitazioni WHERE id_esercitazione=?", (es[0],))
                    cursor.execute("DELETE FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                    cursor.execute("DELETE FROM presenze WHERE id_seduta=?", (id_s,))
                cursor.execute("DELETE FROM sedute WHERE societa=? OR id_societa=?", (soc, id_soc))

                cursor.execute("SELECT id_giocatore FROM giocatori WHERE societa=? OR id_societa=?", (soc, id_soc))
                id_giocatori = [r[0] for r in cursor.fetchall()]
                if id_giocatori:
                    placeholders = ",".join("?" for _ in id_giocatori)
                    cursor.execute(f"DELETE FROM presenze WHERE id_giocatore IN ({placeholders})", id_giocatori)
                cursor.execute("DELETE FROM giocatori WHERE societa=? OR id_societa=?", (soc, id_soc))

                cursor.execute("DELETE FROM macrociclo WHERE societa=? OR id_societa=?", (soc, id_soc))

                if res_soc:
                    cursor.execute("DELETE FROM cartelle_societa WHERE id_societa=?", (res_soc[0],))

                conn.commit()
            finally:
                conn.close()
        else:
            r = requests.delete(f"{INDIRIZZO_SERVER}/macrocicli/societa", params={"societa": soc}, headers=_headers(dati_utente), timeout=10)
            if r.status_code != 200:
                try:
                    dettaglio = r.json().get("detail", "Eliminazione fallita sul Cloud.")
                except Exception:
                    dettaglio = "Eliminazione fallita sul Cloud."
                raise Exception(dettaglio)

    # ==========================================
    # MODULO: MACROCICLO
    # ==========================================
    @staticmethod
    def get_macrocicli_gruppi(dati_utente):
        raggruppamenti = {}
        indipendenti = []
        is_offline = dati_utente.get("offline", False)

        if is_offline:
            conn = None
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                cursor.execute("SELECT DISTINCT categoria, stagione, societa, creato_da FROM macrociclo")
                for r in cursor.fetchall():
                    cat, stag, soc, creato_da = r[0], r[1], r[2] if r[2] else "", r[3] if r[3] else "Locale"
                    if DataManager.ha_permesso_cartella(dati_utente, soc, cat):
                        gruppo = {"categoria": cat, "stagione": stag, "societa": soc, "creato_da": creato_da}
                        if soc:
                            if soc not in raggruppamenti: raggruppamenti[soc] = []
                            raggruppamenti[soc].append(gruppo)
                        else:
                            indipendenti.append(gruppo)
            except Exception as e:
                print("Errore:", e)
            finally:
                # FIX: conn.close() era raggiungibile solo sul percorso di
                # successo (dentro il try, dopo il ciclo): un errore a metà
                # query lasciava la connessione sqlite aperta per sempre.
                if conn: conn.close()
        else:
            try:
                risposta = requests.get(f"{INDIRIZZO_SERVER}/macrocicli/gruppi", headers=_headers(dati_utente), timeout=3)
                if risposta.status_code == 200:
                    for gruppo in risposta.json():
                        cat, soc = gruppo.get("categoria"), gruppo.get("societa", "").strip()
                        if DataManager.ha_permesso_cartella(dati_utente, soc, cat):
                            if soc:
                                if soc not in raggruppamenti: raggruppamenti[soc] = []
                                raggruppamenti[soc].append(gruppo)
                            else:
                                indipendenti.append(gruppo)
            except: pass
        return raggruppamenti, indipendenti

    @staticmethod
    def elimina_macrociclo_gruppo(dati_utente, cat, stag, soc):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            # FIX: enforcement permessi mancante (vedi elimina_societa_completa).
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            # FIX: filtro esatto invece di "(societa=? OR societa IS NULL OR
            # societa='')" - quel filtro, riusato qui per una CANCELLAZIONE
            # invece che per un elenco, faceva sì che eliminare il gruppo di
            # un club specifico cancellasse ANCHE un macrociclo indipendente
            # (senza club) con la stessa categoria+stagione.
            cond, param = _filtro_societa_esatto(soc)
            params = [cat, stag] + ([param] if param is not None else [])
            cursor.execute(f"DELETE FROM macrociclo WHERE categoria=? AND stagione=? AND {cond}", params)
            conn.commit(); conn.close()
        else:
            r = requests.delete(f"{INDIRIZZO_SERVER}/macrocicli", params={"stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=3)
            if r.status_code != 200:
                raise Exception(f"Eliminazione macrociclo fallita sul Cloud: {r.text}")

    @staticmethod
    def sposta_gruppo_dati(dati_utente, cat, stag, soc_vecchia, soc_nuova):
        is_offline = dati_utente.get("offline", False)
        soc_v = soc_vecchia.strip() if soc_vecchia else ""
        soc_n = soc_nuova.strip() if soc_nuova else ""

        if is_offline:
            # FIX: enforcement permessi mancante - senza questo controllo un
            # utente poteva spostare dati da/verso un club a cui non ha
            # accesso. Verifichiamo sia l'origine che la destinazione (con
            # auto-claim se una delle due società non è ancora reclamata da
            # nessuno, stesso comportamento di _assicura_permesso_scrittura).
            DataManager._assicura_permesso_scrittura(dati_utente, soc_v, cat)
            DataManager._assicura_permesso_scrittura(dati_utente, soc_n, cat)

            conn = _connetti_locale()
            cursor = conn.cursor()
            cond_n, param_n = _filtro_societa_esatto(soc_n)
            params_check = [cat, stag] + ([param_n] if param_n is not None else [])
            cursor.execute(f"SELECT 1 FROM macrociclo WHERE categoria=? AND stagione=? AND {cond_n}", params_check)
            if cursor.fetchone():
                conn.close()
                raise Exception(f"Esiste già un macrociclo {cat} ({stag}) nella destinazione.")

            mio_id = dati_utente.get("id_utente", "locale_admin")
            # FIX: come altrove, la vecchia INSERT OR IGNORE si affidava al
            # vincolo UNIQUE case-sensitive di SQLite; ora passiamo dal
            # resolver comune, case-insensitive, per non generare un "club
            # fantasma" duplicato se soc_n differisce solo per maiuscole o
            # spazi da un club già esistente.
            id_soc_n, nome_soc_n = _risolvi_societa_locale(cursor, soc_n, mio_id)

            # FIX: filtro esatto sull'origine (soc_v) invece di "(societa=?
            # OR societa IS NULL OR societa='')" - quel filtro, usato per uno
            # SPOSTAMENTO invece che per un elenco, faceva sì che spostare il
            # gruppo di un club specifico trascinasse con sé anche dati
            # indipendenti (senza club) con la stessa categoria+stagione.
            cond_v, param_v = _filtro_societa_esatto(soc_v)
            params_v = [nome_soc_n, id_soc_n, cat, stag] + ([param_v] if param_v is not None else [])
            cursor.execute(f"UPDATE macrociclo SET societa=?, id_societa=? WHERE categoria=? AND stagione=? AND {cond_v}", params_v)
            cursor.execute(f"UPDATE sedute SET societa=?, id_societa=? WHERE categoria=? AND stagione=? AND {cond_v}", params_v)
            cursor.execute(f"UPDATE giocatori SET societa=?, id_societa=? WHERE categoria=? AND stagione=? AND {cond_v}", params_v)

            # FIX: rimosso il vecchio INSERT "auto-grant Master" ridondante
            # qui (era anche parte del bug più ampio spiegato nel docstring
            # di _assicura_permesso_scrittura: controllava solo se QUESTO
            # utente non avesse già una riga, non se il club fosse
            # realmente non reclamato da nessuno). L'auto-claim sulla
            # destinazione, quando genuinamente non reclamata, è già
            # gestito sopra da _assicura_permesso_scrittura(soc_n).

            conn.commit()
            conn.close()
        else:
            payload = {"categoria": cat, "stagione": stag, "societa_vecchia": soc_v, "societa_nuova": soc_n}
            r = requests.put(f"{INDIRIZZO_SERVER}/macrocicli/sposta", json=payload, headers=_headers(dati_utente), timeout=5)
            if r.status_code != 200:
                raise Exception(r.json().get("detail", "Errore nello spostamento sul Cloud."))

    @staticmethod
    def get_macrociclo(dati_utente, cat, stag, soc):
        dati_macrociclo = []
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            # FIX: filtro esatto invece di "(societa=? OR societa IS NULL OR
            # societa='')" - quel filtro, usato per LEGGERE un gruppo
            # specifico invece che per un elenco aggregato, faceva sì che le
            # settimane di un macrociclo INDIPENDENTE (senza club) con la
            # stessa categoria+stagione comparissero anche dentro il gruppo
            # di un club specifico (segnalato da Luca: Presenze mostrava
            # eventi non presenti nel Macrociclo su cui stava lavorando).
            cond, param = _filtro_societa_esatto(soc)
            params = [cat, stag] + ([param] if param is not None else [])
            cursor.execute(f"SELECT * FROM macrociclo WHERE categoria=? AND stagione=? AND {cond}", params)
            righe = cursor.fetchall()
            col_names = [description[0] for description in cursor.description]
            dati_macrociclo = [dict(zip(col_names, row)) for row in righe]
            conn.close()
        else:
            try:
                risposta = requests.get(f"{INDIRIZZO_SERVER}/macrocicli", params={"stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=5)
                if risposta.status_code == 200: dati_macrociclo = risposta.json()
            except Exception as e:
                print(f"Errore API macrociclo: {e}")
        return dati_macrociclo

    @staticmethod
    def salva_macrociclo_batch(dati_utente, settimane_payload, cat, stag, soc):
        is_offline = dati_utente.get("offline", False)

        # FIX: enforcement permessi mancante (vedi elimina_societa_completa).
        # Usa _assicura_permesso_scrittura (non il semplice
        # ha_permesso_cartella) perché questa è la funzione che crea il
        # PRIMO macrociclo di un club nuovo: nessuno ha ancora un permesso
        # su una società che non esiste ancora, quindi il controllo deve
        # poter concedere l'accesso al suo stesso creatore.
        if is_offline:
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)

        # FIX: se una cella del giorno risulta senza tipo (vuota), non deve
        # portarsi dietro un riferimento a id_seduta: altrimenti la seduta
        # resta collegata "fantasma" nel DB (esiste ancora con la sua data,
        # ma è invisibile in questa griglia perché la cella è vuota), il che
        # produce conteggi sbagliati altrove (es. la prossima seduta in
        # Dashboard). Rete di sicurezza a livello di salvataggio, in aggiunta
        # alla conferma già richiesta in interfaccia_macrociclo.py quando
        # l'utente cambia manualmente il tipo di una cella collegata.
        giorni = ["lun", "mar", "mer", "gio", "ven", "sab", "dom"]
        for p in settimane_payload:
            for gg in giorni:
                if not (p.get(gg) or "").strip():
                    p[f"id_seduta_{gg}"] = None

        # FIX: rimosso il vecchio INSERT "auto-grant Master" ridondante e
        # buggato qui: controllava solo "questo utente non ha ancora un
        # permesso su questo club" invece di "nessuno ha ancora un permesso
        # su questo club", quindi QUALUNQUE utente offline poteva
        # auto-assegnarsi Master su un club ALTRUI già reclamato da
        # qualcun altro, semplicemente salvando un macrociclo con quel
        # nome (vedi docstring di _assicura_permesso_scrittura, già
        # invocata sopra e che gestisce correttamente l'auto-claim solo
        # quando il club non è reclamato da nessuno).

        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            id_soc, nome_soc = _risolvi_societa_locale(cursor, soc, dati_utente.get("id_utente", "locale_admin"))
            # FIX: filtro esatto invece di "(societa=? OR societa IS NULL OR
            # societa='')" - riscrivere il macrociclo di un club specifico non
            # deve poter cancellare anche un macrociclo indipendente con la
            # stessa categoria+stagione.
            cond, param = _filtro_societa_esatto(soc)
            params_del = [cat, stag] + ([param] if param is not None else [])
            cursor.execute(f"DELETE FROM macrociclo WHERE categoria=? AND stagione=? AND {cond}", params_del)
            for p in settimane_payload:
                p = dict(p)
                p["societa"] = nome_soc
                p["id_societa"] = id_soc
                cols = ", ".join(p.keys()); ph = ", ".join(["?"] * len(p))
                cursor.execute(f"INSERT INTO macrociclo ({cols}) VALUES ({ph})", list(p.values()))
            conn.commit(); conn.close()
        else:
            risposta = requests.post(f"{INDIRIZZO_SERVER}/macrocicli/batch", json=settimane_payload, headers=_headers(dati_utente), timeout=5)
            if risposta.status_code != 200: raise Exception("Salvataggio fallito sul Cloud.")

    @staticmethod
    def crea_gruppo_con_settimane(dati_utente, cat, stag, soc):
        """Crea un nuovo gruppo di Macrociclo con TUTTE le settimane della
        stagione già pronte (vuote), invece di nascere senza nessuna e
        doverle aggiungere una alla volta con "Aggiungi settimana": stesso
        dizionario "vuoto" già costruito da MacrocicloVM.aggiungiSettimana,
        un id_settimana progressivo per ciascuna, poi un unico
        salva_macrociclo_batch (riusato com'è, nessun INSERT duplicato)."""
        numero_settimane = calcola_numero_settimane_stagione(stag)
        settimane = []
        for id_settimana in range(1, numero_settimane + 1):
            riga = {
                "id_settimana": id_settimana, "stagione": stag, "categoria": cat,
                "periodo": _periodo_predefinito_settimana(stag, id_settimana),
                "obiettivo_tecnico": "", "obiettivo_tattico": "", "obiettivo_condizionale": "", "note": "",
            }
            for gg in GIORNI:
                riga[gg] = ""
            settimane.append(riga)
        DataManager.salva_macrociclo_batch(dati_utente, settimane, cat, stag, soc)
        return numero_settimane

    # ==========================================
    # MODULO: ANAGRAFICA
    # ==========================================
    @staticmethod
    def get_anagrafica_gruppi(dati_utente):
        macro_attivi = set(); giocatori_attuali = set()
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = None
            try:
                conn = _connetti_locale(); cursor = conn.cursor()
                cursor.execute("SELECT DISTINCT categoria, stagione, societa FROM macrociclo")
                for r in cursor.fetchall():
                    if DataManager.ha_permesso_cartella(dati_utente, r[2] or "", r[0]): macro_attivi.add((r[0], r[1], r[2] or ""))
                cursor.execute("SELECT DISTINCT categoria, stagione, societa FROM giocatori")
                for r in cursor.fetchall():
                    if DataManager.ha_permesso_cartella(dati_utente, r[2] or "", r[0]): giocatori_attuali.add((r[0], r[1], r[2] or ""))
            except Exception as e:
                print(f"Errore recupero gruppi anagrafica: {e}")
            finally:
                # FIX: conn.close() era raggiungibile solo sul percorso di
                # successo - un errore a metà query lasciava la connessione
                # sqlite aperta per sempre.
                if conn: conn.close()
        else:
            try:
                r_m = requests.get(f"{INDIRIZZO_SERVER}/macrocicli/gruppi", headers=_headers(dati_utente), timeout=3)
                if r_m.status_code == 200:
                    for m in r_m.json():
                        soc = m.get("societa", "").strip()
                        if DataManager.ha_permesso_cartella(dati_utente, soc, m["categoria"]): macro_attivi.add((m["categoria"], m["stagione"], soc))
                r_g = requests.get(f"{INDIRIZZO_SERVER}/giocatori/gruppi", headers=_headers(dati_utente), timeout=3)
                if r_g.status_code == 200:
                    for g in r_g.json():
                        soc = g.get("societa", "").strip()
                        if DataManager.ha_permesso_cartella(dati_utente, soc, g["categoria"]): giocatori_attuali.add((g["categoria"], g["stagione"], soc))
            except: pass
        tutti = macro_attivi | giocatori_attuali
        raggruppamenti = {}; indipendenti = []
        for cat, stag, soc in tutti:
            is_attivo = (cat, stag, soc) in macro_attivi
            item_data = {"cat": cat, "stag": stag, "soc": soc, "is_attivo": is_attivo, "is_folder": False}
            if soc:
                if soc not in raggruppamenti: raggruppamenti[soc] = []
                raggruppamenti[soc].append(item_data)
            else: indipendenti.append(item_data)
        return macro_attivi, raggruppamenti, indipendenti

    @staticmethod
    def elimina_gruppo_giocatori(dati_utente, cat, stag, soc):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            # FIX: enforcement permessi mancante (vedi elimina_societa_completa).
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            # FIX: filtro esatto invece di "(societa=? OR societa IS NULL OR
            # societa='')" per le stesse ragioni di elimina_macrociclo_gruppo:
            # eliminare il gruppo giocatori di un club specifico non deve
            # coinvolgere anche giocatori indipendenti con la stessa
            # categoria+stagione.
            cond, param = _filtro_societa_esatto(soc)
            params = [cat, stag] + ([param] if param is not None else [])
            cursor.execute(f"SELECT 1 FROM macrociclo WHERE categoria=? AND stagione=? AND {cond}", params)
            if cursor.fetchone(): conn.close(); raise Exception("Macrociclo esistente!")
            cursor.execute(f"SELECT id_giocatore FROM giocatori WHERE categoria=? AND stagione=? AND {cond}", params)
            ids = [r[0] for r in cursor.fetchall()]
            if ids:
                placeholders = ",".join("?" for _ in ids)
                cursor.execute(f"DELETE FROM presenze WHERE id_giocatore IN ({placeholders})", ids)
            cursor.execute(f"DELETE FROM giocatori WHERE categoria=? AND stagione=? AND {cond}", params)
            conn.commit(); conn.close()
        else:
            check_macro = requests.get(f"{INDIRIZZO_SERVER}/macrocicli", params={"stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=3)
            if check_macro.status_code == 200 and len(check_macro.json()) > 0: raise Exception("Macrociclo esistente!")
            requests.delete(f"{INDIRIZZO_SERVER}/giocatori/gruppo", params={"stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=3)

    @staticmethod
    def elimina_gruppo_completo(dati_utente, cat, stag, soc):
        """Elimina un intero gruppo (categoria+stagione+società): sedute
        collegate (con esercitazioni/fasi/presenze a cascata via
        elimina_gruppo_sedute), poi il Macrociclo, infine i giocatori (e le
        loro presenze). L'ordine conta: elimina_gruppo_giocatori rifiuta se
        esiste ancora un Macrociclo collegato (protezione pensata per
        l'eliminazione PARZIALE che prima viveva solo in Anagrafica) -
        cancellando prima sedute e macrociclo quel controllo passa
        naturalmente, senza dover toccare la firma della funzione né il suo
        comportamento per eventuali altri chiamanti."""
        DataManager.elimina_gruppo_sedute(dati_utente, cat, stag, soc)
        DataManager.elimina_macrociclo_gruppo(dati_utente, cat, stag, soc)
        DataManager.elimina_gruppo_giocatori(dati_utente, cat, stag, soc)

    @staticmethod
    def get_giocatori(dati_utente, cat, stag, soc, includi_eliminati=False):
        """includi_eliminati=False (default) esclude i giocatori eliminati
        (soft-delete, vedi delete_giocatore): giusto per l'anagrafica attiva
        di un gruppo e per qualunque selezione di giocatori per un evento
        NUOVO. True include anche gli eliminati con "attivo": False nel
        dict restituito - usato dalle viste storiche (Presenze/Statistiche)
        dove un giocatore eliminato deve continuare a comparire con i suoi
        eventi passati invece di sparire insieme a lui."""
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            # FIX: filtro esatto, stesso motivo di get_macrociclo sopra - un
            # giocatore indipendente (senza club) con la stessa
            # categoria+stagione di un club specifico non deve comparire
            # nell'anagrafica di quel club.
            cond, param = _filtro_societa_esatto(soc)
            params = [cat, stag] + ([param] if param is not None else [])
            cond_attivo = "" if includi_eliminati else " AND attivo=1"
            cursor.execute(f"SELECT id_giocatore, nome, cognome, attivo FROM giocatori WHERE categoria=? AND stagione=? AND {cond}{cond_attivo} ORDER BY cognome, nome", params)
            res = [{"id_giocatore": r[0], "nome": r[1], "cognome": r[2], "attivo": bool(r[3])} for r in cursor.fetchall()]; conn.close(); return res
        else:
            r = requests.get(f"{INDIRIZZO_SERVER}/giocatori", params={"stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=5)
            return r.json() if r.status_code == 200 else []

    @staticmethod
    def update_giocatore(dati_utente, id_g, nome, cognome):
        if dati_utente.get("offline"):
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                # FIX: enforcement permessi mancante. Qui non abbiamo
                # categoria/società passate dal chiamante: le recuperiamo dal
                # giocatore stesso prima di modificarlo.
                cursor.execute("SELECT categoria, societa FROM giocatori WHERE id_giocatore=?", (id_g,))
                riga = cursor.fetchone()
                if riga:
                    DataManager._assicura_permesso_scrittura(dati_utente, riga[1] or "", riga[0])
                cursor.execute("UPDATE giocatori SET nome=?, cognome=? WHERE id_giocatore=?", (nome, cognome, id_g))
                conn.commit()
            finally:
                conn.close()
        else:
            r = requests.put(f"{INDIRIZZO_SERVER}/giocatori/{id_g}", json={"nome": nome, "cognome": cognome}, headers=_headers(dati_utente), timeout=3)
            if r.status_code != 200:
                raise Exception(f"Salvataggio giocatore fallito sul Cloud: {r.text}")

    @staticmethod
    def add_giocatore(dati_utente, nome, cognome, cat, stag, soc):
        if dati_utente.get("offline"):
            # FIX: enforcement permessi mancante (vedi elimina_societa_completa).
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            id_soc, nome_soc = _risolvi_societa_locale(cursor, soc, dati_utente.get("id_utente", "locale_admin"))
            cursor.execute("INSERT INTO giocatori (nome, cognome, stagione, categoria, societa, id_societa) VALUES (?, ?, ?, ?, ?, ?)", (nome, cognome, stag, cat, nome_soc, id_soc)); conn.commit(); conn.close()
        else:
            r = requests.post(f"{INDIRIZZO_SERVER}/giocatori", json={"nome": nome, "cognome": cognome, "stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=3)
            if r.status_code != 200:
                raise Exception(f"Creazione giocatore fallita sul Cloud: {r.text}")

    @staticmethod
    def delete_giocatore(dati_utente, id_g):
        """Soft-delete (attivo=0), non piu' un DELETE fisico: il giocatore
        eliminato dal mister "in corsa" resta in archivio con le presenze
        gia' registrate (visibile in Presenze/Statistiche/griglie per gli
        eventi passati in cui era davvero convocato/presente), ma sparisce
        dall'anagrafica attiva e da qualunque selezione per un evento NUOVO
        (get_giocatori di default esclude gli inattivi - vedi
        includi_eliminati). Nessun evento futuro gli viene marcato: per
        quelli restera' "Null" (nessuna riga in "presenze"), esattamente
        come un giocatore aggiunto DOPO un evento passato."""
        if dati_utente.get("offline"):
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                # FIX: enforcement permessi mancante (vedi update_giocatore).
                cursor.execute("SELECT categoria, societa FROM giocatori WHERE id_giocatore=?", (id_g,))
                riga = cursor.fetchone()
                if riga:
                    DataManager._assicura_permesso_scrittura(dati_utente, riga[1] or "", riga[0])
                cursor.execute("UPDATE giocatori SET attivo=0 WHERE id_giocatore=?", (id_g,))
                conn.commit()
            finally:
                conn.close()
        else:
            r = requests.delete(f"{INDIRIZZO_SERVER}/giocatori/{id_g}", headers=_headers(dati_utente), timeout=3)
            if r.status_code != 200:
                raise Exception(f"Eliminazione giocatore fallita sul Cloud: {r.text}")

    # ==========================================
    # MODULO: SEDUTE & COACHING BOARD ARCHIVE
    # ==========================================
    @staticmethod
    def get_archivio_coaching_board():
        conn = None
        try:
            conn = _connetti_locale(); cur = conn.cursor()
            cur.execute("SELECT id_board, mezzo_allenamento, percorso_immagine, titolo FROM coaching_board ORDER BY id_board DESC")
            return cur.fetchall()
        except Exception as e:
            print(f"Errore recupero archivio board: {e}")
            return []
        finally:
            # FIX: conn.close() era raggiungibile solo sul percorso di
            # successo - un errore a metà query lasciava la connessione
            # sqlite aperta per sempre.
            if conn: conn.close()

    @staticmethod
    def get_dati_vettoriali_board(id_board):
        """Dati vettoriali/descrizione/aspetto campo di UNA lavagna, per
        id_board (chiave univoca).

        FIX: prima cercava per percorso_immagine (il nome file calcolato da
        mezzo+titolo, es. "Torello - Senza Titolo.png") - due lavagne
        diverse con lo stesso mezzo e lo stesso titolo (o entrambe senza
        titolo) calcolano lo STESSO percorso, quindi la query restituiva
        arbitrariamente la riga di una qualunque delle due: aprire una
        lavagna con miniatura corretta poteva mostrare il contenuto (vuoto o
        di un'altra lavagna) sbagliato (segnalato da Luca)."""
        conn = None
        try:
            conn = _connetti_locale(); cur = conn.cursor()
            cur.execute("SELECT dati_vettoriali, descrizione, modalita_campo, colore_campo, colore_linee FROM coaching_board WHERE id_board=?", (id_board,))
            return cur.fetchone()
        except Exception as e:
            print(f"Errore recupero dati vettoriali board: {e}")
            return None
        finally:
            if conn: conn.close()

    @staticmethod
    def percorso_board_in_uso_da_altro(percorso, id_board_corrente):
        """True se un'ALTRA lavagna (id_board diverso, o None per una
        lavagna nuova mai salvata) usa gia' questo percorso_immagine -
        salvare su un percorso condiviso sovrascriverebbe silenziosamente
        il file PNG (quindi la miniatura) dell'altra lavagna."""
        conn = None
        try:
            conn = _connetti_locale(); cur = conn.cursor()
            if id_board_corrente:
                cur.execute("SELECT 1 FROM coaching_board WHERE percorso_immagine=? AND id_board!=?", (percorso, id_board_corrente))
            else:
                cur.execute("SELECT 1 FROM coaching_board WHERE percorso_immagine=?", (percorso,))
            return cur.fetchone() is not None
        except Exception as e:
            print(f"Errore verifica percorso board: {e}")
            return False
        finally:
            if conn: conn.close()

    @staticmethod
    def elimina_coaching_board(id_board):
        conn = _connetti_locale()
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT percorso_immagine FROM coaching_board WHERE id_board=?", (id_board,))
            row = cursor.fetchone()
            cursor.execute("DELETE FROM coaching_board WHERE id_board=?", (id_board,))
            conn.commit()
            # Ripulisce anche il file immagine associato, invece di lasciarlo
            # orfano sul disco per sempre.
            if row and row[0] and os.path.exists(row[0]):
                try: os.remove(row[0])
                except OSError: pass
        finally:
            conn.close()

    @staticmethod
    def cartella_grafiche_board():
        """Cartella dove vengono salvate le anteprime PNG delle lavagne
        tattiche (stessa convenzione gia' in uso: "Grafiche_Board/[categoria]
        mezzo_allenamento - titolo.png"), creata se non esiste ancora."""
        percorso = os.path.join(BASE_DIR, "Grafiche_Board")
        os.makedirs(percorso, exist_ok=True)
        return percorso

    @staticmethod
    def cartella_pdf_sedute():
        """Cartella dove viene esportato il PDF di una seduta, stessa
        convenzione di cartella_grafiche_board() (creata se non esiste)."""
        percorso = os.path.join(BASE_DIR, "PDF_Sedute")
        os.makedirs(percorso, exist_ok=True)
        return percorso

    @staticmethod
    def cartella_report_presenze():
        """Cartella dove viene esportata la Griglia Mensile presenze in CSV,
        stessa convenzione di cartella_pdf_sedute() (creata se non esiste)."""
        percorso = os.path.join(BASE_DIR, "Report_Presenze")
        os.makedirs(percorso, exist_ok=True)
        return percorso

    @staticmethod
    def salva_coaching_board(id_board, titolo, mezzo_allenamento, descrizione, percorso_immagine, dati_vettoriali,
                              modalita_campo="intero", colore_campo="#1e7d32", colore_linee="#ffffff"):
        """Crea (id_board None) o aggiorna una lavagna tattica salvata.

        NOTA: prima di questa sessione non esisteva alcuna funzione di
        salvataggio centralizzata per questa tabella in DataManager -
        l'editor precedente (interfaccia_coaching_board.py, cancellato con
        tutto il resto del vecchio prototipo) scriveva su sqlite
        direttamente dalla UI, un'eccezione architetturale rispetto a ogni
        altro modulo di questo file. Qui si torna al pattern comune
        (_connetti_locale, try/finally).

        FIX: rimossa "categoria" dalle proprieta' salvabili (richiesta di
        Luca): la colonna resta nello schema per compatibilita' con le
        lavagne gia' salvate, ma non viene piu' letta ne' scritta qui.

        FIX: modalita_campo/colore_campo/colore_linee non erano affatto
        persistite - riaprire una lavagna mostrava sempre "Campo intero" e i
        colori di default (segnalato da Luca)."""
        conn = _connetti_locale()
        try:
            cursor = conn.cursor()
            if id_board:
                cursor.execute(
                    "UPDATE coaching_board SET titolo=?, mezzo_allenamento=?, descrizione=?, percorso_immagine=?, dati_vettoriali=?, modalita_campo=?, colore_campo=?, colore_linee=? WHERE id_board=?",
                    (titolo, mezzo_allenamento, descrizione, percorso_immagine, dati_vettoriali, modalita_campo, colore_campo, colore_linee, id_board),
                )
                conn.commit()
                return id_board
            else:
                cursor.execute(
                    "INSERT INTO coaching_board (titolo, mezzo_allenamento, descrizione, percorso_immagine, dati_vettoriali, modalita_campo, colore_campo, colore_linee) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                    (titolo, mezzo_allenamento, descrizione, percorso_immagine, dati_vettoriali, modalita_campo, colore_campo, colore_linee),
                )
                conn.commit()
                return cursor.lastrowid
        finally:
            conn.close()

    @staticmethod
    def get_sedute_contenitori(dati_utente):
        is_offline = dati_utente.get("offline", False)

        macro_attivi = []
        sedute_esistenti = {}

        if is_offline:
            conn = None
            try:
                conn = _connetti_locale(); cursor = conn.cursor()
                cursor.execute("SELECT DISTINCT categoria, stagione, societa FROM macrociclo")
                for r in cursor.fetchall():
                    soc = r[2] if r[2] else ""
                    if DataManager.ha_permesso_cartella(dati_utente, soc, r[0]): macro_attivi.append((r[0], r[1], soc))
                cursor.execute("SELECT categoria, stagione, societa, COUNT(id_seduta) FROM sedute WHERE numero_seduta != 'Partita' GROUP BY categoria, stagione, societa")
                for r in cursor.fetchall():
                    soc = r[2] if r[2] else ""
                    if DataManager.ha_permesso_cartella(dati_utente, soc, r[0]): sedute_esistenti[(r[0], r[1], soc)] = r[3]
            except Exception as e:
                print(f"Errore recupero contenitori sedute: {e}")
            finally:
                # FIX: conn.close() era raggiungibile solo sul percorso di
                # successo - un errore a metà query lasciava la connessione
                # sqlite aperta per sempre.
                if conn: conn.close()
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/macrocicli/gruppi", headers=_headers(dati_utente), timeout=3)
                if r.status_code == 200:
                    for m in r.json():
                        soc = m.get("societa") or ""
                        if DataManager.ha_permesso_cartella(dati_utente, soc, m["categoria"]): macro_attivi.append((m["categoria"], m["stagione"], soc))
                r = requests.get(f"{INDIRIZZO_SERVER}/sedute/gruppi", headers=_headers(dati_utente), timeout=3)
                if r.status_code == 200:
                    for s in r.json():
                        soc = s.get("societa") or ""
                        if DataManager.ha_permesso_cartella(dati_utente, soc, s["categoria"]): sedute_esistenti[(s["categoria"], s["stagione"], soc)] = s["conteggio"]
            except: pass

        # FIX: iterare direttamente su un set() di tuple (cat, stag, soc) ha
        # un ordine che dipende dall'hash delle stringhe, randomizzato per
        # processo in Python: get_riepilogo_dashboard tronca poi questa
        # lista a "limite_gruppi" elementi, quindi QUALI gruppi finiscono nel
        # riepilogo poteva cambiare in modo non deterministico da un avvio
        # all'altro dell'app, a parità di dati. sorted() rende l'ordine
        # riproducibile.
        tutti = sorted(set(macro_attivi + list(sedute_esistenti.keys())))
        raggruppamenti = {}; indipendenti = []

        for cat, stag, soc in tutti:
            conteggio = sedute_esistenti.get((cat, stag, soc), 0)
            is_attivo = (cat, stag, soc) in macro_attivi
            item_data = {"cat": cat, "stag": stag, "soc": soc, "is_attivo": is_attivo, "conteggio": conteggio, "is_folder": False}
            if soc:
                if soc not in raggruppamenti: raggruppamenti[soc] = []
                raggruppamenti[soc].append(item_data)
            else: indipendenti.append(item_data)
        return macro_attivi, raggruppamenti, indipendenti

    @staticmethod
    def get_sedute_lista(dati_utente, cat, stag, soc):
        is_offline = dati_utente.get("offline", False)
        cat_p = cat.strip() if cat else ""
        stag_p = stag.strip() if stag else ""
        soc_p = soc.strip() if soc else ""

        if is_offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                # FIX: confronto esatto invece di "(... = ? OR ... = '')" -
                # quel filtro, usato per LEGGERE il gruppo di un club
                # specifico invece che per un elenco aggregato, faceva sì che
                # le sedute di un gruppo INDIPENDENTE (senza club) con la
                # stessa categoria+stagione comparissero anche dentro il
                # gruppo di un club specifico.
                cond_soc = "TRIM(COALESCE(societa, '')) = ?" if soc_p else "TRIM(COALESCE(societa, '')) = ''"
                query = f"""
                    SELECT id_seduta, numero_seduta, data_seduta
                    FROM sedute
                    WHERE TRIM(categoria) = ?
                    AND TRIM(stagione) = ?
                    AND {cond_soc}
                    AND numero_seduta != 'Partita'
                    ORDER BY data_seduta ASC
                """
                params = (cat_p, stag_p, soc_p) if soc_p else (cat_p, stag_p)
                cursor.execute(query, params)
                res = [{"id_seduta": r[0], "numero_seduta": r[1], "data_seduta": r[2]} for r in cursor.fetchall()]
                conn.close()
                return res
            except Exception as e:
                print(f"Errore query sedute: {e}")
                return []
        else:
            try:
                params = {"stagione": stag_p, "categoria": cat_p, "societa": soc_p}
                r = requests.get(f"{INDIRIZZO_SERVER}/sedute", params=params, headers=_headers(dati_utente), timeout=5)
                return [s for s in r.json() if s.get("numero_seduta") != "Partita"] if r.status_code == 200 else []
            except Exception as e:
                print(f"Errore API sedute: {e}")
                return []

    @staticmethod
    def get_sedute_mese(dati_utente, cat, stag, soc, mese_aaaa_mm):
        """Sedute (incluse le 'Partita') di un dato mese AAAA-MM per una
        categoria/stagione/società. Usato dal registro presenze/statistiche
        per evitare di caricare l'intero storico e poi filtrarlo in Python."""
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            # FIX: mancava del tutto un try/except - un errore sqlite qui
            # (es. DB bloccato) risaliva grezzo fino al chiamante e lasciava
            # la connessione mai chiusa, senza alcuna pulizia.
            conn = _connetti_locale()
            try:
                cursor = conn.cursor()
                # FIX: filtro esatto, stesso motivo delle altre get_* sopra -
                # un gruppo indipendente (senza club) con la stessa
                # categoria+stagione non deve comparire nel report mensile
                # di un club specifico.
                cond, param = _filtro_societa_esatto(soc)
                params = [cat, stag] + ([param] if param is not None else []) + [f"{mese_aaaa_mm}-%"]
                cursor.execute(
                    "SELECT id_seduta, data_seduta, numero_seduta FROM sedute "
                    f"WHERE categoria=? AND stagione=? AND {cond} "
                    "AND data_seduta LIKE ? ORDER BY data_seduta ASC",
                    params,
                )
                return cursor.fetchall()
            except Exception as e:
                print(f"Errore recupero sedute del mese: {e}")
                return []
            finally:
                conn.close()
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/sedute", params={"stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=5)
            except Exception as e:
                print(f"Errore API sedute del mese: {e}")
                return []
            if r.status_code != 200:
                return []
            return [
                (s["id_seduta"], s["data_seduta"], s.get("numero_seduta"))
                for s in r.json() if str(s.get("data_seduta", "")).startswith(mese_aaaa_mm)
            ]

    @staticmethod
    def get_sedute_lista_completa(dati_utente, cat, stag, soc):
        """Come get_sedute_lista, ma senza escludere le sedute con
        numero_seduta == 'Partita': usata dal registro presenze/calendario,
        che deve poter mostrare e collegare anche quelle."""
        is_offline = dati_utente.get("offline", False)
        cat_p = (cat or "").strip(); stag_p = (stag or "").strip(); soc_p = (soc or "").strip()
        if is_offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                # FIX: confronto esatto invece di "(... = ? OR ... = '')" -
                # stesso motivo di get_sedute_lista/get_macrociclo sopra: le
                # sedute di un gruppo INDIPENDENTE (senza club) con la
                # stessa categoria+stagione non devono comparire nel
                # registro presenze/calendario di un club specifico.
                cond_soc = "TRIM(COALESCE(societa,''))=?" if soc_p else "TRIM(COALESCE(societa,''))=''"
                params = (cat_p, stag_p, soc_p) if soc_p else (cat_p, stag_p)
                cursor.execute(
                    "SELECT id_seduta, numero_seduta, data_seduta FROM sedute "
                    "WHERE TRIM(categoria)=? AND TRIM(stagione)=? "
                    f"AND {cond_soc} "
                    "ORDER BY data_seduta ASC",
                    params,
                )
                res = [{"id_seduta": r[0], "numero_seduta": r[1], "data_seduta": r[2]} for r in cursor.fetchall()]
                conn.close()
                return res
            except Exception as e:
                print(f"Errore query sedute (completa): {e}")
                return []
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/sedute", params={"stagione": stag_p, "categoria": cat_p, "societa": soc_p}, headers=_headers(dati_utente), timeout=5)
                return r.json() if r.status_code == 200 else []
            except Exception as e:
                print(f"Errore API sedute (completa): {e}")
                return []

    @staticmethod
    def cerca_globale(dati_utente, testo):
        """Ricerca su gruppi/giocatori/sedute visibili all'utente (barra
        "Cerca" globale). Riusa le stesse funzioni/filtri di permesso già
        usate dalle singole schermate (get_anagrafica_gruppi/get_giocatori/
        get_sedute_lista_completa) invece di una query aggregata nuova: i
        gruppi visibili sono pochi per utente, quindi N query piccole
        restano più che accettabili rispetto al rischio di duplicare la
        logica di permessi in una query SQL/HTTP ad hoc."""
        testo_norm = (testo or "").strip().lower()
        if len(testo_norm) < 2:
            return []
        try:
            _, raggruppamenti, indipendenti = DataManager.get_anagrafica_gruppi(dati_utente)
        except Exception:
            return []
        gruppi = list(indipendenti)
        for lista in raggruppamenti.values():
            gruppi.extend(lista)

        risultati = []
        for g in gruppi:
            cat, stag, soc = g["cat"], g["stag"], g.get("soc") or ""
            etichetta_gruppo = f"{soc + ' · ' if soc else ''}{cat} — {stag}"

            if testo_norm in etichetta_gruppo.lower():
                risultati.append({"tipo": "gruppo", "label": etichetta_gruppo, "cat": cat, "stag": stag, "soc": soc, "idSeduta": 0})

            try:
                giocatori = DataManager.get_giocatori(dati_utente, cat, stag, soc)
            except Exception:
                giocatori = []
            for gio in giocatori:
                nome_completo = f"{gio['nome']} {gio['cognome']}"
                if testo_norm in nome_completo.lower():
                    risultati.append({"tipo": "giocatore", "label": f"{nome_completo} — {etichetta_gruppo}", "cat": cat, "stag": stag, "soc": soc, "idSeduta": 0})

            try:
                sedute = DataManager.get_sedute_lista_completa(dati_utente, cat, stag, soc)
            except Exception:
                sedute = []
            for s in sedute:
                etichetta_seduta = f"{s.get('data_seduta', '')} — {s.get('numero_seduta', '')}"
                if testo_norm in etichetta_seduta.lower():
                    risultati.append({"tipo": "seduta", "label": f"{etichetta_seduta} · {etichetta_gruppo}", "cat": cat, "stag": stag, "soc": soc, "idSeduta": s.get("id_seduta", 0)})

        return risultati[:30]

    @staticmethod
    def crea_seduta_e_collega_macrociclo(dati_utente, cat, stag, soc, data_str, numero_seduta, id_settimana, giorno_col, tipo=None):
        """Crea una nuova seduta e la collega alla cella del macrociclo
        corrispondente (id_seduta_<gg>, ed eventualmente il tipo impegno).
        Centralizza una logica che in precedenza era duplicata (e implementata
        due volte, una per l'offline e una per il cloud) dentro
        interfaccia_presenze.py con query dirette."""
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            # FIX: enforcement permessi mancante (vedi elimina_societa_completa).
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                id_soc, nome_soc = _risolvi_societa_locale(cursor, soc, dati_utente.get("id_utente", "locale_admin"))
                cursor.execute(
                    "INSERT INTO sedute (data_seduta, numero_seduta, categoria, stagione, societa, id_societa) VALUES (?, ?, ?, ?, ?, ?)",
                    (data_str, numero_seduta, cat, stag, nome_soc, id_soc),
                )
                nuovo_id = cursor.lastrowid
                # FIX: filtro esatto invece di "(societa=? OR societa IS NULL
                # OR societa='')" - collegare la nuova seduta alla cella
                # giusta del macrociclo non deve poter aggiornare per errore
                # una riga di macrociclo indipendente con la stessa
                # settimana/stagione/categoria ma nessun club.
                cond, param = _filtro_societa_esatto(soc)
                # FIX: l'UPDATE era incondizionato - si fidava solo del
                # controllo "cella gia' collegata?" fatto lato VM (chiamante)
                # sulla sua copia in memoria, che puo' essere stale (es.
                # Macrociclo aperto PRIMA che Presenze colleghi la stessa
                # cella dal Calendario & Eventi). Risultato reale osservato:
                # una seconda chiamata da uno stato non aggiornato sovrascrive
                # silenziosamente un id_seduta_<gg> gia' corretto con uno
                # vecchio/sbagliato, orfanizzando la seduta appena scritta
                # (esisteva ancora con le sue presenze, ma nessuna cella la
                # referenziava piu' - invisibile a Griglia Mensile/Macrociclo).
                # Si verifica prima lo stato REALE su DB (non quello passato
                # dal chiamante): se la riga della settimana non esiste
                # ancora (raro in produzione - crea_gruppo_con_settimane crea
                # sempre tutte le settimane della stagione - ma capita se
                # quella settimana e' stata eliminata nel frattempo) la si
                # crea al volo gia' con il collegamento; se esiste ma la
                # cella e' gia' occupata, si annulla la seduta appena creata
                # invece di rubare il collegamento.
                cursor.execute(
                    f"SELECT id_seduta_{giorno_col} FROM macrociclo WHERE id_settimana=? AND stagione=? AND categoria=? AND {cond}",
                    [id_settimana, stag, cat] + ([param] if param is not None else []),
                )
                riga_esistente = cursor.fetchone()
                if riga_esistente is None:
                    colonne = ["id_settimana", "stagione", "categoria", "societa", "id_societa", f"id_seduta_{giorno_col}"]
                    valori = [id_settimana, stag, cat, nome_soc, id_soc, nuovo_id]
                    if tipo is not None:
                        colonne.append(giorno_col)
                        valori.append(tipo)
                    cursor.execute(
                        f"INSERT INTO macrociclo ({', '.join(colonne)}) VALUES ({', '.join('?' for _ in colonne)})",
                        valori,
                    )
                elif riga_esistente[0] is not None:
                    cursor.execute("DELETE FROM sedute WHERE id_seduta=?", (nuovo_id,))
                    conn.commit()
                    raise Exception("Questa cella e' stata collegata nel frattempo da un'altra azione. Aggiorna la schermata e riprova.")
                else:
                    if tipo is not None:
                        params = [tipo, nuovo_id, id_settimana, stag, cat] + ([param] if param is not None else [])
                        cursor.execute(
                            f"UPDATE macrociclo SET {giorno_col}=?, id_seduta_{giorno_col}=? WHERE id_settimana=? AND stagione=? AND categoria=? AND {cond} AND id_seduta_{giorno_col} IS NULL",
                            params,
                        )
                    else:
                        params = [nuovo_id, id_settimana, stag, cat] + ([param] if param is not None else [])
                        cursor.execute(
                            f"UPDATE macrociclo SET id_seduta_{giorno_col}=? WHERE id_settimana=? AND stagione=? AND categoria=? AND {cond} AND id_seduta_{giorno_col} IS NULL",
                            params,
                        )
                    if cursor.rowcount == 0:
                        cursor.execute("DELETE FROM sedute WHERE id_seduta=?", (nuovo_id,))
                        conn.commit()
                        raise Exception("Questa cella e' stata collegata nel frattempo da un'altra azione. Aggiorna la schermata e riprova.")
                conn.commit()
                return nuovo_id
            finally:
                conn.close()
        else:
            payload_seduta = {"data_seduta": data_str, "numero_seduta": numero_seduta, "categoria": cat, "stagione": stag, "societa": soc}
            r = requests.post(f"{INDIRIZZO_SERVER}/sedute", json=payload_seduta, headers=_headers(dati_utente), timeout=5)
            if r.status_code != 200:
                raise Exception(f"Creazione seduta fallita: {r.text}")
            nuovo_id = r.json()["id_seduta"]
            payload_macro = {"stagione": stag, "categoria": cat, "societa": soc, "id_settimana": id_settimana, "giorno": giorno_col, "id_seduta": nuovo_id}
            if tipo is not None:
                payload_macro["tipo"] = tipo
            requests.put(f"{INDIRIZZO_SERVER}/macrocicli/cella", json=payload_macro, headers=_headers(dati_utente), timeout=5)
            return nuovo_id

    @staticmethod
    def collega_seduta_esistente_a_macrociclo(dati_utente, cat, stag, soc, id_settimana, giorno_col, id_seduta, tipo=None):
        """Collega alla cella una seduta GIA' esistente (creata a parte in
        Sedute, non ancora agganciata a nessuna cella) invece di crearne una
        nuova - complementare a crea_seduta_e_collega_macrociclo, stessa
        query di scrittura ma senza l'INSERT su sedute. "tipo", se passato,
        pianifica anche la cella (colonna <gg>) nella stessa scrittura - usato
        dal collegamento automatico di SeduteVM.nuovaSeduta quando la cella
        e' ancora completamente vuota (nessun tipo impegno scelto)."""
        if giorno_col not in GIORNI:
            return
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                cond, param = _filtro_societa_esatto(soc)
                # FIX: stesso difetto di crea_seduta_e_collega_macrociclo -
                # UPDATE incondizionato, si fidava solo del controllo lato VM
                # (potenzialmente stale) invece dello stato reale su DB. "AND
                # id_seduta_<gg> IS NULL" impedisce di rubare un collegamento
                # gia' fatto da un'altra azione nel frattempo.
                if tipo is not None:
                    params = [tipo, id_seduta, id_settimana, stag, cat] + ([param] if param is not None else [])
                    cursor.execute(
                        f"UPDATE macrociclo SET {giorno_col}=?, id_seduta_{giorno_col}=? WHERE id_settimana=? AND stagione=? AND categoria=? AND {cond} AND id_seduta_{giorno_col} IS NULL",
                        params,
                    )
                else:
                    params = [id_seduta, id_settimana, stag, cat] + ([param] if param is not None else [])
                    cursor.execute(
                        f"UPDATE macrociclo SET id_seduta_{giorno_col}=? WHERE id_settimana=? AND stagione=? AND categoria=? AND {cond} AND id_seduta_{giorno_col} IS NULL",
                        params,
                    )
                if cursor.rowcount == 0:
                    conn.commit()
                    raise Exception("Questa cella e' stata collegata nel frattempo da un'altra azione. Aggiorna la schermata e riprova.")
                conn.commit()
            finally:
                conn.close()
        else:
            payload = {"stagione": stag, "categoria": cat, "societa": soc, "id_settimana": id_settimana, "giorno": giorno_col, "id_seduta": id_seduta}
            if tipo is not None:
                payload["tipo"] = tipo
            requests.put(f"{INDIRIZZO_SERVER}/macrocicli/cella", json=payload, headers=_headers(dati_utente), timeout=5)

    @staticmethod
    def scollega_seduta_da_macrociclo(dati_utente, cat, stag, soc, id_settimana, giorno):
        """Scollega (SENZA eliminare) la seduta agganciata a una cella del
        macrociclo: la seduta resta nel DB con le sue presenze/fasi, la
        cella torna libera di essere ricollegata o di crearne una nuova.
        Complementare a elimina_singola_seduta, che invece cancella anche la
        seduta stessa."""
        if giorno not in GIORNI:
            return
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                cond, param = _filtro_societa_esatto(soc)
                params = [id_settimana, stag, cat] + ([param] if param is not None else [])
                cursor.execute(
                    f"UPDATE macrociclo SET id_seduta_{giorno}=NULL WHERE id_settimana=? AND stagione=? AND categoria=? AND {cond}",
                    params,
                )
                conn.commit()
            finally:
                conn.close()
        else:
            payload = {"stagione": stag, "categoria": cat, "societa": soc, "id_settimana": id_settimana, "giorno": giorno, "id_seduta": None}
            requests.put(f"{INDIRIZZO_SERVER}/macrocicli/cella", json=payload, headers=_headers(dati_utente), timeout=5)

    @staticmethod
    def salva_board_partita(dati_utente, cat, stag, soc, id_settimana, giorno, dati_json):
        """Scrive il JSON strutturato della "Board Partita" (avversario,
        luogo, risultato, goal/note per giocatore convocato) nella colonna
        nota_<giorno> del macrociclo - stesso formato/colonna gia' usato
        dal vecchio widget (interfaccia_macrociclo.py, DialogBoardPartita),
        qui semplicemente riletto e riscritto da un ViewModel invece che da
        un QDialog."""
        if giorno not in GIORNI:
            return
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                cond, param = _filtro_societa_esatto(soc)
                params = [dati_json, id_settimana, stag, cat] + ([param] if param is not None else [])
                cursor.execute(
                    f"UPDATE macrociclo SET nota_{giorno}=? WHERE id_settimana=? AND stagione=? AND categoria=? AND {cond}",
                    params,
                )
                conn.commit()
            finally:
                conn.close()
        else:
            payload = {"stagione": stag, "categoria": cat, "societa": soc, "id_settimana": id_settimana, "giorno": giorno, "nota": dati_json}
            requests.put(f"{INDIRIZZO_SERVER}/macrocicli/cella", json=payload, headers=_headers(dati_utente), timeout=5)

    @staticmethod
    def elimina_singola_seduta(dati_utente, id_s):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            # FIX: manca(va) sia l'enforcement permessi sia try/finally -
            # un errore a metà cancellazione lasciava la connessione aperta
            # con una transazione parziale (vedi audit). Recuperiamo
            # categoria/società della seduta per il controllo permessi PRIMA
            # di cancellare qualunque cosa.
            try:
                cursor.execute("SELECT categoria, societa FROM sedute WHERE id_seduta=?", (id_s,))
                riga = cursor.fetchone()
                if riga:
                    DataManager._assicura_permesso_scrittura(dati_utente, riga[1] or "", riga[0])
                cursor.execute("SELECT id_esercitazione FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                for es in cursor.fetchall():
                    cursor.execute("DELETE FROM esercitazioni WHERE id_esercitazione=?", (es[0],))
                cursor.execute("DELETE FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                cursor.execute("DELETE FROM presenze WHERE id_seduta=?", (id_s,))
                cursor.execute("DELETE FROM sedute WHERE id_seduta=?", (id_s,))
                for gg in GIORNI:
                    # FIX: mancava di azzerare nota_<giorno> (la "Board Partita":
                    # avversario, luogo, risultato...) insieme al collegamento.
                    # La nota restava quindi salvata sulla riga di macrociclo e
                    # veniva ripresentata pari pari se in seguito si creava una
                    # nuova seduta sulla stessa cella (stesso giorno/settimana),
                    # facendo sembrare che i vecchi dati della partita eliminata
                    # non fossero mai stati davvero cancellati.
                    cursor.execute(f"UPDATE macrociclo SET id_seduta_{gg}=NULL, {gg}=' ', nota_{gg}='' WHERE id_seduta_{gg}=?", (id_s,))
                conn.commit()
            finally:
                conn.close()
        else:
            r = requests.delete(f"{INDIRIZZO_SERVER}/sedute/{id_s}", headers=_headers(dati_utente), timeout=5)
            if r.status_code != 200:
                raise Exception(f"Eliminazione seduta fallita sul Cloud: {r.text}")

    @staticmethod
    def elimina_gruppo_sedute(dati_utente, cat, stag, soc):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            # FIX: enforcement permessi mancante (vedi elimina_societa_completa).
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                # FIX: filtro esatto invece di "(societa=? OR societa IS NULL
                # OR societa='')" - eliminare l'archivio sedute di un club
                # specifico non deve poter cancellare anche sedute
                # indipendenti con la stessa categoria+stagione.
                cond, param = _filtro_societa_esatto(soc)
                params = [cat, stag] + ([param] if param is not None else [])
                cursor.execute(f"SELECT id_seduta FROM sedute WHERE categoria=? AND stagione=? AND {cond}", params)
                sedute_ids = [row[0] for row in cursor.fetchall()]
                for id_s in sedute_ids:
                    cursor.execute("SELECT id_esercitazione FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                    for es in cursor.fetchall():
                        cursor.execute("DELETE FROM esercitazioni WHERE id_esercitazione=?", (es[0],))
                    cursor.execute("DELETE FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                    cursor.execute("DELETE FROM presenze WHERE id_seduta=?", (id_s,))
                    for gg in GIORNI:
                        # Stesso FIX di elimina_singola_seduta: azzerare anche
                        # nota_<giorno> (Board Partita), non solo il
                        # collegamento e il tipo.
                        cursor.execute(f"UPDATE macrociclo SET id_seduta_{gg}=NULL, {gg}=' ', nota_{gg}='' WHERE id_seduta_{gg}=?", (id_s,))
                cursor.execute(f"DELETE FROM sedute WHERE categoria=? AND stagione=? AND {cond}", params)
                conn.commit()
            finally:
                conn.close()
        else:
            r = requests.delete(f"{INDIRIZZO_SERVER}/sedute/gruppo", params={"stagione": stag, "categoria": cat, "societa": soc}, headers=_headers(dati_utente), timeout=5)
            if r.status_code != 200:
                raise Exception(f"Eliminazione archivio sedute fallita sul Cloud: {r.text}")

    @staticmethod
    def get_seduta_dettaglio(dati_utente, id_s):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            # FIX: conn.close() era raggiungibile solo sui percorsi di
            # successo (riga vuota o fine funzione): un errore a metà lettura
            # lasciava la connessione sqlite aperta per sempre.
            conn = _connetti_locale()
            try:
                cursor = conn.cursor()
                cursor.execute("SELECT * FROM sedute WHERE id_seduta=?", (id_s,))
                row_s = cursor.fetchone()
                if not row_s: return None
                col_s = [desc[0] for desc in cursor.description]
                d = dict(zip(col_s, row_s))

                cursor.execute("SELECT * FROM fasi_seduta WHERE id_seduta=? ORDER BY ordine_blocco", (id_s,))
                fasi_rows = cursor.fetchall()
                col_f = [desc[0] for desc in cursor.description]
                fasi = []
                for fr in fasi_rows:
                    f_dict = dict(zip(col_f, fr))
                    cursor.execute("SELECT * FROM esercitazioni WHERE id_esercitazione=?", (f_dict["id_esercitazione"],))
                    es_row = cursor.fetchone()
                    if es_row:
                        col_e = [desc[0] for desc in cursor.description]
                        # FIX (loop di binding in Sedute.qml): colonne TEXT nullable,
                        # una riga esercitazioni scritta con un campo NULL (dato
                        # legacy) tornava qui come None invece di "" - il ComboBox
                        # editabile lo rilegge come editText="" al primo giro,
                        # diverso dal None salvato, e il confronto in
                        # impostaCampoEsercitazione non lo intercetta: emette
                        # dettaglioCambiato, il Repeater (model non incrementale)
                        # ricrea tutti i delegate, loop rilevato da Qt.
                        f_dict["esercitazione"] = {k: (v if v is not None else "") for k, v in zip(col_e, es_row)}
                    else:
                        f_dict["esercitazione"] = {"mezzo_allenamento": "", "obiettivo_tecnico": "", "obiettivo_tattico": "", "descrizione": "", "immagine": ""}
                    fasi.append(f_dict)
                d["fasi"] = fasi
                return d
            except Exception as e:
                print(e)
                return None
            finally:
                conn.close()
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/sedute/dettaglio/{id_s}", headers=_headers(dati_utente), timeout=5)
                return r.json() if r.status_code == 200 else None
            except: return None

    @staticmethod
    def salva_seduta_strutturata(dati_utente, id_s, ds, ns, cat, stag, gioc, soc, societa_stampa, fasi_payload, obiettivo_principale=""):
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            # FIX: enforcement permessi mancante (vedi elimina_societa_completa).
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                id_soc, nome_soc = _risolvi_societa_locale(cursor, soc, dati_utente.get("id_utente", "locale_admin"))
                if id_s:
                    cursor.execute("UPDATE sedute SET data_seduta=?, numero_seduta=?, categoria=?, stagione=?, giocatori=?, societa=?, id_societa=?, societa_stampa=?, obiettivo_principale=? WHERE id_seduta=?",
                                   (ds, ns, cat, stag, gioc, nome_soc, id_soc, societa_stampa, obiettivo_principale, id_s))
                    cursor.execute("SELECT id_esercitazione FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                    for oe in cursor.fetchall(): cursor.execute("DELETE FROM esercitazioni WHERE id_esercitazione=?", (oe[0],))
                    cursor.execute("DELETE FROM fasi_seduta WHERE id_seduta=?", (id_s,))
                else:
                    cursor.execute("INSERT INTO sedute (data_seduta, numero_seduta, categoria, stagione, giocatori, societa, id_societa, societa_stampa, obiettivo_principale) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                   (ds, ns, cat, stag, gioc, nome_soc, id_soc, societa_stampa, obiettivo_principale))
                    id_s = cursor.lastrowid

                for fase in fasi_payload:
                    # FIX: contratto incoerente - nome_esercizio/descrizione/
                    # immagine venivano letti con [...] (KeyError se assenti)
                    # mentre due chiavi dello stesso dict due righe sotto
                    # usavano già .get(..., ""). Uniformato a .get(...) con
                    # default, così un payload con un campo mancante non fa
                    # fallire l'intero salvataggio (con connessione e
                    # transazione lasciate a metà, prima del fix del blocco
                    # try/finally qui sotto).
                    es = fase.get("esercitazione", {})
                    cursor.execute("INSERT INTO esercitazioni (nome_esercizio, mezzo_allenamento, obiettivo_tecnico, obiettivo_tattico, descrizione, immagine) VALUES (?, ?, ?, ?, ?, ?)",
                                   (es.get("nome_esercizio", ""), es.get("mezzo_allenamento", ""), es.get("obiettivo_tecnico", ""), es.get("obiettivo_tattico", ""), es.get("descrizione", ""), es.get("immagine", "")))
                    id_es = cursor.lastrowid
                    cursor.execute("INSERT INTO fasi_seduta (id_seduta, ordine_blocco, nome_blocco, fase, durata_minuti, id_esercitazione) VALUES (?, ?, ?, ?, ?, ?)",
                                   (id_s, fase.get("ordine_blocco"), fase.get("nome_blocco"), fase.get("fase", ""), fase.get("durata_minuti", 0), id_es))
                conn.commit()
                return id_s
            finally:
                conn.close()
        else:
            payload = {"id_seduta": id_s, "data_seduta": ds, "numero_seduta": ns, "categoria": cat, "stagione": stag, "giocatori": gioc, "societa": soc, "societa_stampa": societa_stampa, "obiettivo_principale": obiettivo_principale, "fasi": fasi_payload}
            r = requests.post(f"{INDIRIZZO_SERVER}/sedute", json=payload, headers=_headers(dati_utente), timeout=5)
            if r.status_code == 200: return r.json()["id_seduta"]
            else: raise Exception(f"Salvataggio server fallito: {r.text}")

    @staticmethod
    def carica_liste_menu(offline=False):
        DEF_MEZZI = ["Esercizio analitico", "Attività motoria/coordinativa", "Situazione di gioco semplice", "Situazione di gioco complessa", "Gioco di possesso", "Gioco di posizione", "Small Sided Game", "Duelli", "Large Sided Game", "Partita"]
        # Stesse liste standard di Obiettivo Tecnico/Tattico del Macrociclo
        # (categorie 'Tecnici'/'Tattici' condivise nella stessa tabella
        # menu_tendine): tenerle allineate qui evita che le due schermate
        # mostrino di default due elenchi diversi per lo stesso concetto.
        DEF_TEC = ["Nessuno", "Conduzione", "Finte", "Tiro in porta", "Trasmissione/Ricezione", "Colpo di testa", "Contrasto"]
        DEF_TAT = ["Nessuno", "Smarcamento", "Scelte offensive", "Scelte difensive", "Superiorità/Inferiorità numerica", "Marcamento"]

        if offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                # FIX: prima il seeding dei valori di default scattava ogni
                # volta che una categoria risultava vuota - non solo la
                # prima volta in assoluto, ma anche dopo che l'utente aveva
                # cancellato TUTTE le voci di una categoria di proposito: ad
                # ogni riavvio dell'app le voci cancellate ricomparivano
                # (segnalato da un collega di Luca). Il flag
                # "menu_tendine_seminato" in impostazioni_sistema (tabella
                # chiave/valore gia' presente nello schema) garantisce che la
                # semina avvenga una volta sola in assoluto per queste 3
                # categorie: dopo, una categoria vuota resta semplicemente
                # vuota, non un segnale di "non ancora inizializzata".
                cursor.execute("SELECT 1 FROM impostazioni_sistema WHERE chiave='menu_tendine_seminato'")
                if not cursor.fetchone():
                    cursor.execute("SELECT COUNT(*) FROM menu_tendine WHERE categoria='Mezzi'")
                    if cursor.fetchone()[0] == 0:
                        cursor.executemany("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", [("Mezzi", v) for v in DEF_MEZZI])
                    cursor.execute("SELECT COUNT(*) FROM menu_tendine WHERE categoria='Tecnici'")
                    if cursor.fetchone()[0] == 0:
                        cursor.executemany("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", [("Tecnici", v) for v in DEF_TEC])
                    cursor.execute("SELECT COUNT(*) FROM menu_tendine WHERE categoria='Tattici'")
                    if cursor.fetchone()[0] == 0:
                        cursor.executemany("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", [("Tattici", v) for v in DEF_TAT])
                    cursor.execute("INSERT INTO impostazioni_sistema (chiave, valore) VALUES ('menu_tendine_seminato', '1')")
                    conn.commit()
                cursor.execute("SELECT categoria, valore FROM menu_tendine")
                rows = cursor.fetchall()
                conn.close()
                dati = {'Mezzi': [], 'Tecnici': [], 'Tattici': []}
                for r in rows:
                    if r[0] in dati: dati[r[0]].append(r[1])
                return dati
            except: return {'Mezzi': DEF_MEZZI, 'Tecnici': DEF_TEC, 'Tattici': DEF_TAT}
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/menu", timeout=3)
                if r.status_code == 200:
                    return r.json()
            except: pass
            return {'Mezzi': DEF_MEZZI, 'Tecnici': DEF_TEC, 'Tattici': DEF_TAT}

    @staticmethod
    def carica_liste_menu_gk(offline=False):
        """Equivalente di carica_liste_menu() ma per la Versione GK
        (interfaccia_seduta_gk.py): mezzi di allenamento e obiettivi tecnici
        offensivi/difensivi specifici del preparatore portieri. Usa
        categorie DISTINTE in menu_tendine ('MezziGK'/'TecniciGK'/'TatticiGK')
        così le due versioni non condividono/sovrascrivono le rispettive
        liste standard, pur restando nella stessa tabella (nessuna modifica
        allo schema)."""
        DEF_MEZZI_GK = ["Play", "Analitico", "Globale", "Squadra"]
        DEF_TEC_GK = ["Nessuno", "Rotolamento dal basso", "Trasmissione dall'alto", "Trasmissione", "Lancio lungo", "Rinvio da terra", "Rinvio al volo"]
        DEF_TAT_GK = ["Nessuno", "Posizionamento", "Postura", "Spostamento", "Presa", "Deviazione", "Respinta", "Tuffo", "Uscita alta", "Uscita bassa"]

        if offline:
            try:
                conn = _connetti_locale()
                cursor = conn.cursor()
                # FIX: vedi commento gemello in carica_liste_menu() - flag
                # separato perche' questa e' una schermata/modalita' diversa
                # (Portieri), seminata indipendentemente dalla prima volta
                # che viene aperta, non necessariamente insieme all'altra.
                cursor.execute("SELECT 1 FROM impostazioni_sistema WHERE chiave='menu_tendine_gk_seminato'")
                if not cursor.fetchone():
                    cursor.execute("SELECT COUNT(*) FROM menu_tendine WHERE categoria='MezziGK'")
                    if cursor.fetchone()[0] == 0:
                        cursor.executemany("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", [("MezziGK", v) for v in DEF_MEZZI_GK])
                    cursor.execute("SELECT COUNT(*) FROM menu_tendine WHERE categoria='TecniciGK'")
                    if cursor.fetchone()[0] == 0:
                        cursor.executemany("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", [("TecniciGK", v) for v in DEF_TEC_GK])
                    cursor.execute("SELECT COUNT(*) FROM menu_tendine WHERE categoria='TatticiGK'")
                    if cursor.fetchone()[0] == 0:
                        cursor.executemany("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", [("TatticiGK", v) for v in DEF_TAT_GK])
                    cursor.execute("INSERT INTO impostazioni_sistema (chiave, valore) VALUES ('menu_tendine_gk_seminato', '1')")
                    conn.commit()
                cursor.execute("SELECT categoria, valore FROM menu_tendine WHERE categoria IN ('MezziGK', 'TecniciGK', 'TatticiGK')")
                rows = cursor.fetchall()
                conn.close()
                mappa_cat = {'MezziGK': 'Mezzi', 'TecniciGK': 'Tecnici', 'TatticiGK': 'Tattici'}
                dati = {'Mezzi': [], 'Tecnici': [], 'Tattici': []}
                for r in rows:
                    dati[mappa_cat[r[0]]].append(r[1])
                return dati
            except: return {'Mezzi': DEF_MEZZI_GK, 'Tecnici': DEF_TEC_GK, 'Tattici': DEF_TAT_GK}
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/menu", timeout=3)
                if r.status_code == 200:
                    dati_server = r.json()
                    return {
                        'Mezzi': dati_server.get('MezziGK') or DEF_MEZZI_GK,
                        'Tecnici': dati_server.get('TecniciGK') or DEF_TEC_GK,
                        'Tattici': dati_server.get('TatticiGK') or DEF_TAT_GK,
                    }
            except: pass
            return {'Mezzi': DEF_MEZZI_GK, 'Tecnici': DEF_TEC_GK, 'Tattici': DEF_TAT_GK}

    @staticmethod
    def aggiungi_voce_menu(dati_utente, categoria, valore):
        # FIX: "except: pass" inghiottiva QUALUNQUE errore (anche di
        # programmazione) senza lasciare traccia. Nessun chiamante di questa
        # funzione la avvolge in un proprio try/except (alcuni la invocano
        # anche in cicli di seeding all'avvio schermata): farla sollevare
        # un'eccezione qui creerebbe un rischio concreto di crash non gestito
        # durante il caricamento di una schermata. Manteniamo quindi il
        # comportamento "silenzioso" verso l'utente, ma logghiamo l'errore
        # reale invece di scartarlo del tutto, per poterlo diagnosticare.
        #
        # FIX: prendeva solo un booleano `is_offline`, senza alcun accesso al
        # token di sessione. Il server ora richiede autenticazione su
        # POST/DELETE /menu (in precedenza erano gli unici due endpoint di
        # scrittura raggiungibili senza login): senza questo cambio, ogni
        # "aggiungi voce menu" cloud avrebbe iniziato a fallire silenziosamente
        # con 401 (l'eccezione veniva comunque solo stampata, mai mostrata
        # all'utente). Riceviamo quindi l'intero dati_utente, come fa già
        # _headers() per ogni altra chiamata online di questo file.
        if dati_utente.get("offline", False):
            try:
                conn = _connetti_locale(); cursor = conn.cursor()
                cursor.execute("INSERT INTO menu_tendine (categoria, valore) VALUES (?, ?)", (categoria, valore))
                conn.commit(); conn.close()
            except Exception as e:
                print(f"Errore aggiunta voce menu ({categoria}={valore}): {e}")
        else:
            try:
                requests.post(f"{INDIRIZZO_SERVER}/menu", json={"categoria": categoria, "valore": valore}, headers=_headers(dati_utente), timeout=3)
            except Exception as e:
                print(f"Errore aggiunta voce menu cloud ({categoria}={valore}): {e}")

    @staticmethod
    def rimuovi_voce_menu(dati_utente, categoria, valore):
        if dati_utente.get("offline", False):
            try:
                conn = _connetti_locale(); cursor = conn.cursor()
                cursor.execute("DELETE FROM menu_tendine WHERE categoria=? AND valore=?", (categoria, valore))
                conn.commit(); conn.close()
            except Exception as e:
                print(f"Errore rimozione voce menu ({categoria}={valore}): {e}")
        else:
            try:
                requests.delete(f"{INDIRIZZO_SERVER}/menu", params={"categoria": categoria, "valore": valore}, headers=_headers(dati_utente), timeout=3)
            except Exception as e:
                print(f"Errore rimozione voce menu cloud ({categoria}={valore}): {e}")

    @staticmethod
    def crea_seduta_vuota(dati_utente, data_calc, cat, stag, soc, tipo_impegno="A"):
        is_offline = dati_utente.get("offline", False)
        numero_s = "Da Def." if tipo_impegno == "A" else "Partita"

        if is_offline:
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale()
            try:
                cursor = conn.cursor()
                id_soc, nome_soc = _risolvi_societa_locale(cursor, soc, dati_utente.get("id_utente", "locale_admin"))
                cursor.execute("INSERT INTO sedute (data_seduta, numero_seduta, categoria, stagione, societa, id_societa) VALUES (?, ?, ?, ?, ?, ?)",
                               (data_calc, numero_s, cat, stag, nome_soc, id_soc))
                id_s = cursor.lastrowid
                conn.commit()
                return id_s
            finally:
                conn.close()
        else:
            payload = {"data_seduta": data_calc, "numero_seduta": numero_s, "categoria": cat, "stagione": stag, "societa": soc, "fasi": []}
            try:
                r = requests.post(f"{INDIRIZZO_SERVER}/sedute", json=payload, headers=_headers(dati_utente), timeout=5)
            except Exception as e:
                raise Exception(f"Impossibile contattare il server: {e}")
            if r.status_code != 200:
                raise Exception(f"Creazione seduta fallita sul Cloud: {r.text}")
            return r.json()["id_seduta"]

    # ==========================================
    # MODULO: PRESENZE / STATISTICHE (centralizzato)
    # ==========================================
    # In precedenza interfaccia_presenze.py e interfaccia_statistiche.py
    # aprivano da soli sqlite3.connect()/requests, duplicando (e disallineando)
    # la logica offline/online già presente qui. I metodi seguenti sono
    # l'unico punto in cui questi due moduli devono ora leggere/scrivere dati.

    @staticmethod
    def get_mappa_tipi_seduta(dati_utente, cat, stag, soc=""):
        """Restituisce {id_seduta: tipo_impegno} per l'intero macrociclo di
        una categoria/stagione, leggendo tutte le colonne lun..dom in una sola
        query invece di interrogare una riga alla volta per ogni giorno."""
        mappa = {}
        righe = DataManager.get_macrociclo(dati_utente, cat, stag, soc)
        for riga in righe:
            for gg in GIORNI:
                id_sed = riga.get(f"id_seduta_{gg}")
                if id_sed:
                    mappa[id_sed] = riga.get(gg, "A")
        return mappa

    @staticmethod
    def get_presenze_seduta(dati_utente, id_seduta):
        """Restituisce {id_giocatore: stato} per una singola seduta."""
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            cursor.execute("SELECT id_giocatore, stato FROM presenze WHERE id_seduta=?", (id_seduta,))
            res = {r[0]: r[1] for r in cursor.fetchall()}
            conn.close()
            return res
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/presenze/{id_seduta}", headers=_headers(dati_utente), timeout=5)
                if r.status_code == 200:
                    return {p["id_giocatore"]: p["stato"] for p in r.json()}
            except Exception as e:
                print(f"Errore recupero presenze: {e}")
            return {}

    @staticmethod
    def get_formazione(dati_utente, id_seduta):
        """Restituisce il JSON dati_vettoriali della Formazione salvata per
        questa seduta, o "" se non ne esiste ancora una (nessuna riga)."""
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            cursor.execute("SELECT dati_vettoriali FROM formazione WHERE id_seduta=?", (id_seduta,))
            riga = cursor.fetchone()
            conn.close()
            return riga[0] if riga and riga[0] else ""
        else:
            try:
                r = requests.get(f"{INDIRIZZO_SERVER}/formazione/{id_seduta}", headers=_headers(dati_utente), timeout=5)
                if r.status_code == 200:
                    return r.json().get("dati_vettoriali") or ""
            except Exception as e:
                print(f"Errore recupero formazione: {e}")
            return ""

    @staticmethod
    def salva_formazione(dati_utente, id_seduta, cat, stag, soc, dati_json):
        """Salva (UPSERT per id_seduta, mai piu' di una riga per seduta) il
        JSON dati_vettoriali della Formazione - stessa filosofia non
        versionata di salva_coaching_board/salva_board_partita."""
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            DataManager._assicura_permesso_scrittura(dati_utente, soc, cat)
            conn = _connetti_locale(); cursor = conn.cursor()
            try:
                cursor.execute("SELECT id_formazione FROM formazione WHERE id_seduta=?", (id_seduta,))
                riga = cursor.fetchone()
                if riga:
                    cursor.execute("UPDATE formazione SET dati_vettoriali=? WHERE id_seduta=?", (dati_json, id_seduta))
                else:
                    cursor.execute("INSERT INTO formazione (id_seduta, dati_vettoriali) VALUES (?, ?)", (id_seduta, dati_json))
                conn.commit()
            finally:
                conn.close()
        else:
            payload = {"id_seduta": id_seduta, "stagione": stag, "categoria": cat, "societa": soc, "dati_vettoriali": dati_json}
            requests.put(f"{INDIRIZZO_SERVER}/formazione/{id_seduta}", json=payload, headers=_headers(dati_utente), timeout=5)

    @staticmethod
    def get_presenze_multi_sedute(dati_utente, id_sedute):
        """Restituisce una lista di (id_giocatore, id_seduta, stato) per più
        sedute in una sola query/chiamata, invece di interrogare una seduta
        alla volta in un ciclo (pattern N+1 diffuso nella versione precedente)."""
        if not id_sedute:
            return []
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            placeholders = ",".join("?" for _ in id_sedute)
            cursor.execute(f"SELECT id_giocatore, id_seduta, stato FROM presenze WHERE id_seduta IN ({placeholders})", list(id_sedute))
            res = cursor.fetchall()
            conn.close()
            return res
        else:
            try:
                r = requests.post(f"{INDIRIZZO_SERVER}/presenze/cerca", json=list(id_sedute), headers=_headers(dati_utente), timeout=8)
                if r.status_code == 200:
                    return [(p["id_giocatore"], p["id_seduta"], p["stato"]) for p in r.json()]
            except Exception as e:
                print(f"Errore recupero presenze multiple: {e}")
            return []

    @staticmethod
    def get_dati_allenamento_periodo(dati_utente, id_sedute):
        """Restituisce una lista di dict {mezzo_allenamento, obiettivo_tecnico,
        obiettivo_tattico, durata_minuti}, uno per ogni blocco (fasi_seduta +
        esercitazione collegata) delle sedute indicate. Usato dai grafici a
        torta delle statistiche (Mezzi/Obiettivi Tecnici/Tattici), in una sola
        query/chiamata invece che una per seduta (pattern N+1 della versione
        precedente, oltretutto offline-only)."""
        if not id_sedute:
            return []
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale(); cursor = conn.cursor()
            placeholders = ",".join("?" for _ in id_sedute)
            cursor.execute(f"""
                SELECT e.mezzo_allenamento, e.obiettivo_tecnico, e.obiettivo_tattico, f.durata_minuti
                FROM fasi_seduta f
                JOIN esercitazioni e ON f.id_esercitazione = e.id_esercitazione
                WHERE f.id_seduta IN ({placeholders})
            """, list(id_sedute))
            res = [
                {"mezzo_allenamento": r[0], "obiettivo_tecnico": r[1], "obiettivo_tattico": r[2], "durata_minuti": r[3]}
                for r in cursor.fetchall()
            ]
            conn.close()
            return res
        else:
            try:
                r = requests.post(f"{INDIRIZZO_SERVER}/fasi_seduta/cerca", json=list(id_sedute), headers=_headers(dati_utente), timeout=8)
                if r.status_code == 200:
                    return r.json()
            except Exception as e:
                print(f"Errore recupero dati allenamento: {e}")
            return []

    @staticmethod
    def salva_presenze_seduta(dati_utente, id_seduta, mappa_stati):
        """Salva {id_giocatore: stato} per una seduta. Ritorna (True, None) o
        (False, messaggio_errore): a differenza della versione precedente,
        un fallimento parziale non lascia mai la connessione locale aperta
        con una transazione a metà."""
        is_offline = dati_utente.get("offline", False)
        if is_offline:
            conn = _connetti_locale()
            try:
                cursor = conn.cursor()
                # FIX: enforcement permessi mancante (vedi
                # elimina_societa_completa). Manteniamo il contratto
                # (bool, messaggio) di questa funzione anche per il rifiuto
                # di permesso, invece di sollevare un'eccezione come nelle
                # altre funzioni mutanti.
                cursor.execute("SELECT categoria, societa FROM sedute WHERE id_seduta=?", (id_seduta,))
                riga = cursor.fetchone()
                if riga:
                    try:
                        DataManager._assicura_permesso_scrittura(dati_utente, riga[1] or "", riga[0])
                    except Exception as e:
                        return False, str(e)
                cursor.execute("DELETE FROM presenze WHERE id_seduta=?", (id_seduta,))
                cursor.executemany(
                    "INSERT INTO presenze (id_seduta, id_giocatore, stato) VALUES (?, ?, ?)",
                    [(id_seduta, id_g, stato) for id_g, stato in mappa_stati.items()],
                )
                conn.commit()
                return True, None
            except Exception as e:
                conn.rollback()
                return False, str(e)
            finally:
                conn.close()
        else:
            payload = {"id_seduta": id_seduta, "presenze": [{"id_giocatore": k, "stato": v} for k, v in mappa_stati.items()]}
            try:
                r = requests.post(f"{INDIRIZZO_SERVER}/presenze", json=payload, headers=_headers(dati_utente), timeout=8)
                if r.status_code == 200:
                    return True, None
                return False, r.text
            except Exception as e:
                return False, str(e)

    # ==========================================
    # MODULO: RIEPILOGO DASHBOARD INIZIALE
    # ==========================================
    @staticmethod
    def get_riepilogo_dashboard(dati_utente, giorni_storico=14, limite_gruppi=15):
        """Riepilogo per la schermata iniziale (in precedenza puramente
        decorativa: solo sfondo e saluto, nonostante il bottone della
        sidebar si chiami "Dashboard"): la prossima seduta in programma e
        quante sedute recenti non hanno ancora le presenze registrate,
        aggregando su tutte le categorie/società a cui l'utente ha accesso.

        Qualunque errore (tipicamente di rete, in modalità cloud) viene
        catturato e restituito nel campo "errore" invece di far fallire
        l'intera schermata: l'utente vede un avviso chiaro invece di una
        dashboard che si blocca o mostra dati a metà.
        """
        risultato = {"prossima_seduta": None, "sedute_da_registrare": 0, "sedute_mancanti": [], "errore": None}
        try:
            # La Dashboard è la prima schermata mostrata dopo il login: se
            # l'utente non passa mai da Macrociclo/Sedute (uniche schermate
            # che finora innescavano _esegui_migrazione_sicura_cartelle), la
            # pulizia delle sedute fantasma non veniva mai eseguita e questa
            # schermata continuava a leggere dati non ancora ripuliti.
            # Chiamarla qui garantisce che i dati siano coerenti anche se la
            # Dashboard è l'unica schermata aperta in questa sessione.
            DataManager._esegui_migrazione_sicura_cartelle(dati_utente)
            _, raggruppamenti, indipendenti = DataManager.get_sedute_contenitori(dati_utente)
            gruppi = list(indipendenti)
            for lista in raggruppamenti.values():
                gruppi.extend(lista)
            # Un utente con moltissime categorie/società non deve trasformare
            # l'apertura della dashboard in decine di chiamate di rete: ci
            # fermiamo a un numero ragionevole di gruppi (i primi trovati).
            gruppi = gruppi[:limite_gruppi]

            oggi_str = date.today().isoformat()
            limite_passato_str = (date.today() - timedelta(days=giorni_storico)).isoformat()

            prossima = None
            da_registrare = 0
            # Elenco delle sedute stesse (non solo il conteggio): la Dashboard
            # mostrava solo "N sedute senza presenze registrate" senza dire
            # quali - l'utente doveva andare a cercarle a mano (segnalato).
            sedute_mancanti = []

            for g in gruppi:
                cat, stag, soc = g.get("cat"), g.get("stag"), g.get("soc", "")
                if not cat or not stag:
                    continue
                sedute = DataManager.get_sedute_lista_completa(dati_utente, cat, stag, soc)
                for s in sedute:
                    d = s.get("data_seduta") or ""
                    if not d:
                        continue
                    if d >= oggi_str:
                        if prossima is None or d < prossima["data"]:
                            prossima = {"data": d, "numero": s.get("numero_seduta", ""), "cat": cat, "stag": stag, "soc": soc}
                    elif d >= limite_passato_str:
                        presenze = DataManager.get_presenze_seduta(dati_utente, s["id_seduta"])
                        if not presenze:
                            da_registrare += 1
                            sedute_mancanti.append({
                                "idSeduta": s["id_seduta"], "data": d, "numero": s.get("numero_seduta", ""),
                                "cat": cat, "stag": stag, "soc": soc,
                            })

                # FIX: fino ad ora la "prossima" veniva individuata SOLO
                # scansionando la tabella "sedute", cioè solo se alla cella
                # del macrociclo era già collegata una seduta (creata
                # aprendo Presenze, Board Partita o la seduta stessa). Ma un
                # impegno può benissimo essere già compilato nel macrociclo
                # (tipo A/TM/TA/C) giorni prima che l'utente si preoccupi di
                # collegarci qualcosa: in quel caso, prima di questo fix, la
                # Dashboard non lo vedeva proprio, come se l'impegno non
                # esistesse ancora. Scansioniamo quindi anche le celle del
                # macrociclo stesso, calcolando la data da stagione +
                # settimana + giorno (stessa formula usata per disegnare la
                # griglia), limitandoci alle celle NON ancora collegate a
                # una seduta (quelle collegate sono già coperte dal loop
                # sopra, che legge la data reale della seduta).
                for riga in DataManager.get_macrociclo(dati_utente, cat, stag, soc):
                    id_settimana = riga.get("id_settimana")
                    for gg in GIORNI:
                        if riga.get(f"id_seduta_{gg}"):
                            continue
                        tipo = (riga.get(gg) or "").strip()
                        if not tipo:
                            continue
                        data_cella = _data_cella_macrociclo(stag, id_settimana, gg)
                        if data_cella is None:
                            continue
                        d = data_cella.isoformat()
                        if d >= oggi_str and (prossima is None or d < prossima["data"]):
                            numero = "Partita" if tipo in ("TM", "TA", "C") else "Allenamento"
                            prossima = {"data": d, "numero": numero, "cat": cat, "stag": stag, "soc": soc}

            sedute_mancanti.sort(key=lambda s: s["data"])
            risultato["prossima_seduta"] = prossima
            risultato["sedute_da_registrare"] = da_registrare
            risultato["sedute_mancanti"] = sedute_mancanti
        except Exception as e:
            risultato["errore"] = str(e)
        return risultato
