"""
Fonte UNICA di verità per lo schema del database locale (gestione_squadra.db).

In precedenza lo schema era dichiarato in almeno tre punti diversi e
disallineati tra loro (questo file, il blocco inline in menu_principale.py, e
gli attributi impliciti creati/attesi da data_manager.py e dai vari moduli
interfaccia_*.py): la tabella 'esercitazioni', ad esempio, esisteva con la
colonna 'path_immagine' qui e con 'immagine' altrove, e 'programmazione_macrociclo'
aveva perfino un nome di colonna sintatticamente sbagliato ("mesociclo_obiettivo
tecnico TEXT", con uno spazio) ed era comunque una tabella morta mai usata.

Ora crea_database() è l'unica funzione che crea/aggiorna lo schema; sia
l'avvio dell'app (menu_principale.py) sia l'uso standalone di questo script
richiamano questa stessa funzione, così non possono più divergere.
"""

import os
import sqlite3
import sys

if getattr(sys, 'frozen', False):
    BASE_DIR = os.path.dirname(sys.executable)
else:
    BASE_DIR = os.path.dirname(os.path.abspath(__file__))

DB_LOCALE = os.path.join(BASE_DIR, 'gestione_squadra.db')

_SCHEMA_BASE = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS impostazioni_sistema (
    chiave TEXT PRIMARY KEY,
    valore TEXT
);

CREATE TABLE IF NOT EXISTS giocatori (
    id_giocatore INTEGER PRIMARY KEY AUTOINCREMENT,
    nome TEXT NOT NULL,
    cognome TEXT NOT NULL,
    stagione TEXT,
    categoria TEXT,
    societa TEXT,
    ruolo TEXT,
    data_nascita DATE,
    attivo INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE IF NOT EXISTS presenze (
    id_record INTEGER PRIMARY KEY AUTOINCREMENT,
    id_seduta INTEGER NOT NULL,
    id_giocatore INTEGER NOT NULL,
    stato TEXT NOT NULL,
    FOREIGN KEY (id_giocatore) REFERENCES giocatori (id_giocatore) ON DELETE CASCADE,
    FOREIGN KEY (id_seduta) REFERENCES sedute (id_seduta) ON DELETE CASCADE
);

-- Schema unico e definitivo di 'esercitazioni': in precedenza questo script
-- creava una versione con la colonna 'path_immagine' e senza obiettivi
-- tecnico/tattico, mentre menu_principale.py e il server ne creavano una
-- versione diversa con 'immagine' e con gli obiettivi. Questa è ora la sola
-- versione, identica a quella usata dal resto del codice e dal server.
CREATE TABLE IF NOT EXISTS esercitazioni (
    id_esercitazione INTEGER PRIMARY KEY AUTOINCREMENT,
    nome_esercizio TEXT,
    mezzo_allenamento TEXT,
    obiettivo_tecnico TEXT,
    obiettivo_tattico TEXT,
    descrizione TEXT,
    immagine TEXT
);

CREATE TABLE IF NOT EXISTS sedute (
    id_seduta INTEGER PRIMARY KEY AUTOINCREMENT,
    data_seduta DATE NOT NULL,
    numero_seduta TEXT,
    categoria TEXT,
    stagione TEXT,
    giocatori INTEGER,
    societa TEXT,
    societa_stampa TEXT DEFAULT ''
);

CREATE TABLE IF NOT EXISTS fasi_seduta (
    id_record INTEGER PRIMARY KEY AUTOINCREMENT,
    id_seduta INTEGER NOT NULL,
    ordine_blocco INTEGER NOT NULL,
    nome_blocco TEXT,
    fase TEXT DEFAULT '',
    durata_minuti INTEGER NOT NULL DEFAULT 0,
    id_esercitazione INTEGER,
    FOREIGN KEY (id_seduta) REFERENCES sedute (id_seduta) ON DELETE CASCADE,
    FOREIGN KEY (id_esercitazione) REFERENCES esercitazioni (id_esercitazione) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS macrociclo (
    id_record INTEGER PRIMARY KEY AUTOINCREMENT,
    id_settimana INTEGER,
    stagione TEXT,
    categoria TEXT,
    societa TEXT,
    creato_da TEXT,
    periodo TEXT,
    obiettivo_tecnico TEXT,
    obiettivo_tattico TEXT,
    obiettivo_condizionale TEXT,
    lun TEXT, id_seduta_lun INTEGER, nota_lun TEXT,
    mar TEXT, id_seduta_mar INTEGER, nota_mar TEXT,
    mer TEXT, id_seduta_mer INTEGER, nota_mer TEXT,
    gio TEXT, id_seduta_gio INTEGER, nota_gio TEXT,
    ven TEXT, id_seduta_ven INTEGER, nota_ven TEXT,
    sab TEXT, id_seduta_sab INTEGER, nota_sab TEXT,
    dom TEXT, id_seduta_dom INTEGER, nota_dom TEXT,
    note TEXT
);

CREATE TABLE IF NOT EXISTS menu_tendine (
    id_record INTEGER PRIMARY KEY AUTOINCREMENT,
    categoria TEXT,
    valore TEXT
);

CREATE TABLE IF NOT EXISTS coaching_board (
    id_board INTEGER PRIMARY KEY AUTOINCREMENT,
    mezzo_allenamento TEXT,
    categoria TEXT,
    descrizione TEXT,
    percorso_immagine TEXT,
    dati_vettoriali TEXT,
    titolo TEXT
);

-- Formazione (disposizione dei convocati in campo per un evento partita):
-- a differenza di coaching_board (archivio sciolto, mai legato a una
-- seduta), una riga qui appartiene sempre esattamente a UNA seduta reale
-- (vincolo UNIQUE + FK), sovrascritta ad ogni salvataggio - nessuna
-- cronologia, una sola formazione evolutiva per partita.
CREATE TABLE IF NOT EXISTS formazione (
    id_formazione INTEGER PRIMARY KEY AUTOINCREMENT,
    id_seduta INTEGER NOT NULL UNIQUE,
    dati_vettoriali TEXT,
    FOREIGN KEY (id_seduta) REFERENCES sedute (id_seduta) ON DELETE CASCADE
);

-- Sistema permessi "a cartelle" (societa/categoria), usato in modalità offline.
-- COLLATE NOCASE: rende l'unicità del nome insensibile a maiuscole/minuscole
-- a livello di schema, invece di affidarsi solo al resolver applicativo
-- (_risolvi_societa_locale in data_manager.py) per evitare i "club fantasma"
-- (es. "ASD Test" e "asd test" registrati come due righe distinte).
CREATE TABLE IF NOT EXISTS cartelle_societa (
    id_societa INTEGER PRIMARY KEY AUTOINCREMENT,
    nome TEXT NOT NULL UNIQUE COLLATE NOCASE,
    id_creatore TEXT NOT NULL,
    is_personale INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS cartelle_categorie (
    id_categoria INTEGER PRIMARY KEY AUTOINCREMENT,
    id_societa INTEGER NOT NULL,
    nome TEXT NOT NULL,
    id_creatore TEXT NOT NULL,
    FOREIGN KEY(id_societa) REFERENCES cartelle_societa(id_societa) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS permessi_cartelle (
    id_permesso INTEGER PRIMARY KEY AUTOINCREMENT,
    id_societa INTEGER,
    id_categoria INTEGER,
    id_utente TEXT NOT NULL,
    ruolo TEXT NOT NULL,
    FOREIGN KEY(id_societa) REFERENCES cartelle_societa(id_societa) ON DELETE CASCADE,
    FOREIGN KEY(id_categoria) REFERENCES cartelle_categorie(id_categoria) ON DELETE CASCADE
);
"""

# ALTER TABLE idempotenti per database creati con versioni precedenti dello
# schema (colonne aggiunte nel tempo). Ogni voce è (tabella, colonna, ddl).
_MIGRAZIONI_COLONNE = [
    ("giocatori", "societa", "ALTER TABLE giocatori ADD COLUMN societa TEXT"),
    ("giocatori", "ruolo", "ALTER TABLE giocatori ADD COLUMN ruolo TEXT"),
    ("macrociclo", "societa", "ALTER TABLE macrociclo ADD COLUMN societa TEXT"),
    ("macrociclo", "creato_da", "ALTER TABLE macrociclo ADD COLUMN creato_da TEXT"),
    ("sedute", "societa", "ALTER TABLE sedute ADD COLUMN societa TEXT"),
    # Identità numerica del club (vedi cartelle_societa, già esistente):
    # affiancata al vecchio campo stringa per eliminare le collisioni tra
    # club omonimi e i "club fantasma" generati da spazi/maiuscole diverse
    # tra un salvataggio e l'altro dello stesso nome.
    ("giocatori", "id_societa", "ALTER TABLE giocatori ADD COLUMN id_societa INTEGER"),
    ("macrociclo", "id_societa", "ALTER TABLE macrociclo ADD COLUMN id_societa INTEGER"),
    ("sedute", "id_societa", "ALTER TABLE sedute ADD COLUMN id_societa INTEGER"),
    ("sedute", "societa_stampa", "ALTER TABLE sedute ADD COLUMN societa_stampa TEXT DEFAULT ''"),
    # "Nome blocco" diventa "Fase" (selezione multipla Attivazione/Fase
    # centrale/Fase finale, salvata come CSV, es. "attivazione,centrale").
    ("fasi_seduta", "fase", "ALTER TABLE fasi_seduta ADD COLUMN fase TEXT DEFAULT ''"),
    # Eliminare un giocatore ora e' un soft-delete (attivo=0), non piu' un
    # DELETE fisico: le sue presenze storiche restano visibili in
    # Presenze/Statistiche per gli eventi in cui era davvero registrato,
    # invece di sparire insieme a lui (vedi DataManager.delete_giocatore).
    ("giocatori", "attivo", "ALTER TABLE giocatori ADD COLUMN attivo INTEGER NOT NULL DEFAULT 1"),
    # Testo libero mostrato in alto nel PDF esportato, sopra DATA/CAT/...
    ("sedute", "obiettivo_principale", "ALTER TABLE sedute ADD COLUMN obiettivo_principale TEXT DEFAULT ''"),
    # Prima non erano salvate affatto: riaprire una lavagna tattica
    # mostrava sempre "Campo intero" e i colori di default, anche se
    # all'ultimo salvataggio era impostato "Metà campo" (segnalato da Luca).
    ("coaching_board", "modalita_campo", "ALTER TABLE coaching_board ADD COLUMN modalita_campo TEXT DEFAULT 'intero'"),
    ("coaching_board", "colore_campo", "ALTER TABLE coaching_board ADD COLUMN colore_campo TEXT DEFAULT '#1e7d32'"),
    ("coaching_board", "colore_linee", "ALTER TABLE coaching_board ADD COLUMN colore_linee TEXT DEFAULT '#ffffff'"),
]


def _colonna_esiste(cursor, tabella, colonna):
    cursor.execute(f"PRAGMA table_info({tabella})")
    return any(riga[1] == colonna for riga in cursor.fetchall())


def crea_database(percorso=None):
    """Crea (se mancante) e aggiorna (se già esistente) lo schema del DB locale."""
    conn = sqlite3.connect(percorso or DB_LOCALE)
    try:
        cursor = conn.cursor()
        cursor.executescript(_SCHEMA_BASE)
        for tabella, colonna, ddl in _MIGRAZIONI_COLONNE:
            if not _colonna_esiste(cursor, tabella, colonna):
                try:
                    cursor.execute(ddl)
                except sqlite3.OperationalError as e:
                    # FIX: prima veniva ignorato QUALUNQUE OperationalError,
                    # non solo "duplicate column" (l'unico caso atteso e
                    # innocuo, es. corsa tra due processi che migrano lo
                    # stesso DB in parallelo). Un errore diverso (disco
                    # pieno, DB bloccato...) veniva inghiottito in silenzio e
                    # crea_database() dichiarava comunque successo, pur
                    # mancando una colonna: il problema riemergeva più tardi,
                    # lontano dalla vera causa, come un criptico "no such
                    # column".
                    if "duplicate column" not in str(e).lower():
                        raise
        conn.commit()
    finally:
        conn.close()
    return percorso or DB_LOCALE


if __name__ == '__main__':
    percorso = crea_database()
    print(f"Database '{percorso}' creato/aggiornato con successo!")
