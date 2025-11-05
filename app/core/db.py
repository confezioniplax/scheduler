# core/db.py
from abc import ABC, abstractmethod
from enum import Enum
import traceback
import mysql.connector
import os


# ======================================================
# 1️⃣ Eccezione custom (al posto di HTTPException)
# ======================================================
class SchedulerDbException(Exception):
    """Errore generico per problemi di connessione o query MySQL"""
    def __init__(self, message: str):
        super().__init__(message)


# ======================================================
# 2️⃣ Configurazione (lettura da variabili d'ambiente)
# ======================================================
def get_settings():
    """Restituisce un oggetto con i parametri DB letti da ambiente"""
    class Settings:
        API_MYSQL_HOSTNAME = os.getenv("API_MYSQL_HOSTNAME", "localhost")
        API_MYSQL_PORT = int(os.getenv("API_MYSQL_PORT", "3306"))
        API_MYSQL_USERNAME = os.getenv("API_MYSQL_USERNAME", "root")
        API_MYSQL_PASSWORD = os.getenv("API_MYSQL_PASSWORD", "")
        API_MYSQL_DB = os.getenv("API_MYSQL_DB", "plax")
    return Settings()


# ======================================================
# 3️⃣ Enum: tipo query e tipo connessione
# ======================================================
class QueryType(Enum):
    GET = 1
    INSERT = 2
    UPDATE = 3
    DELETE = 4


class DbConnection(Enum):
    DEFAULT = 1


# ======================================================
# 4️⃣ Classe astratta generica
# ======================================================
class Db(ABC):
    @abstractmethod
    def get_connection(self):
        pass

    @abstractmethod
    def open(self):
        pass

    @abstractmethod
    def execute_query(self, sql, param, fetchall, query_type: QueryType):
        pass

    @abstractmethod
    def close(self):
        pass

    @abstractmethod
    def commit(self):
        pass

    @abstractmethod
    def rollback(self):
        pass


# ======================================================
# 5️⃣ Context manager per usare "with DbManager(MySQLDb()) as db:"
# ======================================================
class DbManager:
    def __init__(self, db_connection: Db):
        self.db = db_connection

    def __enter__(self):
        self.db.open()
        return self.db

    def __exit__(self, exc_type, exc_value, tb):
        if exc_type is not None:
            traceback.print_exception(exc_type, exc_value, tb)
        self.db.close()
        return True


# ======================================================
# 6️⃣ Implementazione MySQL
# ======================================================
class MySQLDb(Db):
    hostname: str = None
    port: int = None
    username: str = None
    password: str = None
    db_name: str = None
    conn = None
    cursor = None

    def __init__(self, connection: DbConnection = DbConnection.DEFAULT):
        if connection == DbConnection.DEFAULT:
            settings = get_settings()
            self.hostname = settings.API_MYSQL_HOSTNAME
            self.port = settings.API_MYSQL_PORT
            self.username = settings.API_MYSQL_USERNAME
            self.password = settings.API_MYSQL_PASSWORD
            self.db_name = settings.API_MYSQL_DB

    # -------------------------
    # Connessione
    # -------------------------
    def get_connection(self):
        try:
            self.conn = mysql.connector.connect(
                user=self.username,
                password=self.password,
                host=self.hostname,
                port=self.port,
                database=self.db_name,
                autocommit=False,
            )
        except mysql.connector.Error as e:
            raise SchedulerDbException(f"Errore connessione MySQL: {e}")

    def open(self):
        self.get_connection()
        self.cursor = self.conn.cursor(dictionary=True)

    # -------------------------
    # Esecuzione query
    # -------------------------
    def execute_query(self, sql, param=(), fetchall: bool = True, query_type: QueryType = QueryType.GET):
        result = None
        try:
            if query_type == QueryType.GET:
                self.cursor.execute(sql, param)
                result = self.cursor.fetchall() if fetchall else self.cursor.fetchone()
            elif query_type in [QueryType.INSERT, QueryType.UPDATE, QueryType.DELETE]:
                self.cursor.execute(sql, param)
                self.conn.commit()
                result = self.cursor.rowcount
        except mysql.connector.Error as e:
            if query_type in [QueryType.INSERT, QueryType.UPDATE, QueryType.DELETE]:
                self.conn.rollback()
            raise SchedulerDbException(f"Errore query MySQL: {e}")
        return result

    # -------------------------
    # Commit / Rollback / Close
    # -------------------------
    def commit(self):
        if self.conn:
            self.conn.commit()

    def rollback(self):
        if self.conn:
            self.conn.rollback()

    def close(self):
        if self.cursor:
            try:
                self.cursor.close()
            except Exception:
                pass
        if self.conn:
            try:
                self.conn.close()
            except Exception:
                pass
