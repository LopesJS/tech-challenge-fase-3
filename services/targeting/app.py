import os
import sys
import logging
import atexit
from functools import wraps

import psycopg2
import requests
from dotenv import load_dotenv
from flask import Flask, request, jsonify
from psycopg2.extras import RealDictCursor, Json
from psycopg2.pool import SimpleConnectionPool

# ---------------------------------------------------------------------
# Configuração de logging
# ---------------------------------------------------------------------
logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------
# Carrega variáveis de ambiente
# ---------------------------------------------------------------------
load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
AUTH_SERVICE_URL = os.getenv("AUTH_SERVICE_URL")

if not DATABASE_URL or not AUTH_SERVICE_URL:
    log.critical(
        "Erro: DATABASE_URL e AUTH_SERVICE_URL devem ser definidos."
    )
    sys.exit(1)

# ---------------------------------------------------------------------
# Inicializa aplicação Flask
# ---------------------------------------------------------------------
app = Flask(__name__)

# ---------------------------------------------------------------------
# Pool de conexões PostgreSQL
# ---------------------------------------------------------------------
try:
    pool = SimpleConnectionPool(1, 5, dsn=DATABASE_URL)
    log.info(
        "Pool de conexões com o PostgreSQL inicializado com sucesso."
    )
except psycopg2.OperationalError as exc:
    log.critical(f"Erro fatal ao conectar ao PostgreSQL: {exc}")
    sys.exit(1)


def close_pool():
    """Fecha todas as conexões do pool ao encerrar o processo."""
    if pool:
        pool.closeall()
        log.info("Pool de conexões PostgreSQL encerrado.")


atexit.register(close_pool)


# ---------------------------------------------------------------------
# Middleware de autenticação
# ---------------------------------------------------------------------
def require_auth(func):
    """Valida a chave de API contra o auth-service."""

    @wraps(func)
    def decorated(*args, **kwargs):
        auth_header = request.headers.get("Authorization")

        if not auth_header:
            return (
                jsonify({"error": "Authorization header obrigatório"}),
                401,
            )

        try:
            validate_url = f"{AUTH_SERVICE_URL}/validate"
            response = requests.get(
                validate_url,
                headers={"Authorization": auth_header},
                timeout=3,
            )

            if response.status_code != 200:
                log.warning(
                    "Falha na validação da chave "
                    f"(status: {response.status_code})"
                )
                return jsonify({"error": "Chave de API inválida"}), 401

        except requests.exceptions.Timeout:
            log.error("Timeout ao conectar com o auth-service")
            return (
                jsonify(
                    {
                        "error": (
                            "Serviço de autenticação indisponível "
                            "(timeout)"
                        )
                    }
                ),
                504,
            )

        except requests.exceptions.RequestException as exc:
            log.error(
                f"Erro ao conectar com o auth-service: {exc}"
            )
            return (
                jsonify(
                    {
                        "error": (
                            "Serviço de autenticação indisponível"
                        )
                    }
                ),
                503,
            )

        return func(*args, **kwargs)

    return decorated


# ---------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------
@app.route("/health", methods=["GET"])
def health():
    """Verifica se aplicação e banco estão disponíveis."""
    conn = None

    try:
        conn = pool.getconn()
        return jsonify({"status": "ok"})
    except Exception as exc:
        log.error(f"Health check falhou: {exc}")
        return jsonify({"status": "db_down"}), 500
    finally:
        if conn:
            pool.putconn(conn)


# ---------------------------------------------------------------------
# Criação de regra
# ---------------------------------------------------------------------
@app.route("/rules", methods=["POST"])
@require_auth
def create_rule():
    """Cria uma nova regra de segmentação."""
    data = request.get_json(silent=True)

    if not data or "flag_name" not in data or "rules" not in data:
        return (
            jsonify(
                {
                    "error": (
                        "'flag_name' e 'rules' (JSON) são obrigatórios"
                    )
                }
            ),
            400,
        )

    flag_name = data["flag_name"]
    rules_obj = data["rules"]
    is_enabled = data.get("is_enabled", True)

    conn = None
    cur = None

    try:
        conn = pool.getconn()
        cur = conn.cursor(cursor_factory=RealDictCursor)

        cur.execute(
            """
            INSERT INTO targeting_rules
            (flag_name, is_enabled, rules, created_at, updated_at)
            VALUES (%s, %s, %s, NOW(), NOW())
            RETURNING *
            """,
            (flag_name, is_enabled, Json(rules_obj)),
        )

        new_rule = cur.fetchone()
        conn.commit()

        log.info(
            f"Regra para '{flag_name}' criada com sucesso."
        )
        return jsonify(new_rule), 201

    except psycopg2.IntegrityError:
        if conn:
            conn.rollback()

        log.warning(
            f"Tentativa de criar regra duplicada: '{flag_name}'"
        )

        return (
            jsonify(
                {
                    "error": (
                        f"Regra para a flag '{flag_name}' já existe"
                    )
                }
            ),
            409,
        )

    except Exception as exc:
        if conn:
            conn.rollback()

        log.error(f"Erro ao criar regra: {exc}")

        return (
            jsonify(
                {
                    "error": "Erro interno do servidor",
                    "details": str(exc),
                }
            ),
            500,
        )

    finally:
        if cur:
            cur.close()

        if conn:
            pool.putconn(conn)


# ---------------------------------------------------------------------
# Busca regra
# ---------------------------------------------------------------------
@app.route("/rules/<string:flag_name>", methods=["GET"])
@require_auth
def get_rule(flag_name):
    """Busca uma regra pelo nome."""
    conn = None
    cur = None

    try:
        conn = pool.getconn()
        cur = conn.cursor(cursor_factory=RealDictCursor)

        cur.execute(
            "SELECT * FROM targeting_rules WHERE flag_name = %s",
            (flag_name,),
        )

        rule = cur.fetchone()

        if not rule:
            return jsonify({"error": "Regra não encontrada"}), 404

        return jsonify(rule)

    except Exception as exc:
        log.error(
            f"Erro ao buscar regra '{flag_name}': {exc}"
        )

        return (
            jsonify(
                {
                    "error": "Erro interno do servidor",
                    "details": str(exc),
                }
            ),
            500,
        )

    finally:
        if cur:
            cur.close()

        if conn:
            pool.putconn(conn)


# ---------------------------------------------------------------------
# Atualiza regra
# ---------------------------------------------------------------------
@app.route("/rules/<string:flag_name>", methods=["PUT"])
@require_auth
def update_rule(flag_name):
    """Atualiza uma regra existente."""
    data = request.get_json(silent=True)

    if not data:
        return jsonify({"error": "Corpo da requisição obrigatório"}), 400

    fields = []
    values = []

    if "rules" in data:
        fields.append("rules = %s")
        values.append(Json(data["rules"]))

    if "is_enabled" in data:
        fields.append("is_enabled = %s")
        values.append(data["is_enabled"])

    if not fields:
        return (
            jsonify(
                {
                    "error": (
                        "Pelo menos um campo "
                        "('rules', 'is_enabled') é obrigatório"
                    )
                }
            ),
            400,
        )

    values.append(flag_name)

    query = (
        f"UPDATE targeting_rules SET {', '.join(fields)} "
        "WHERE flag_name = %s RETURNING *"
    )

    conn = None
    cur = None

    try:
        conn = pool.getconn()
        cur = conn.cursor(cursor_factory=RealDictCursor)

        cur.execute(query, tuple(values))

        if cur.rowcount == 0:
            return jsonify({"error": "Regra não encontrada"}), 404

        updated_rule = cur.fetchone()
        conn.commit()

        log.info(
            f"Regra para '{flag_name}' atualizada com sucesso."
        )

        return jsonify(updated_rule), 200

    except Exception as exc:
        if conn:
            conn.rollback()

        log.error(
            f"Erro ao atualizar regra '{flag_name}': {exc}"
        )

        return (
            jsonify(
                {
                    "error": "Erro interno do servidor",
                    "details": str(exc),
                }
            ),
            500,
        )

    finally:
        if cur:
            cur.close()

        if conn:
            pool.putconn(conn)


# ---------------------------------------------------------------------
# Deleta regra
# ---------------------------------------------------------------------
@app.route("/rules/<string:flag_name>", methods=["DELETE"])
@require_auth
def delete_rule(flag_name):
    """Remove uma regra."""
    conn = None
    cur = None

    try:
        conn = pool.getconn()
        cur = conn.cursor()

        cur.execute(
            "DELETE FROM targeting_rules WHERE flag_name = %s",
            (flag_name,),
        )

        if cur.rowcount == 0:
            return jsonify({"error": "Regra não encontrada"}), 404

        conn.commit()

        log.info(
            f"Regra para '{flag_name}' deletada com sucesso."
        )

        return "", 204

    except Exception as exc:
        if conn:
            conn.rollback()

        log.error(
            f"Erro ao deletar regra '{flag_name}': {exc}"
        )

        return (
            jsonify(
                {
                    "error": "Erro interno do servidor",
                    "details": str(exc),
                }
            ),
            500,
        )

    finally:
        if cur:
            cur.close()

        if conn:
            pool.putconn(conn)


# ---------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------
if __name__ == "__main__":
    port = int(os.getenv("PORT", 8003))
    app.run(host="0.0.0.0", port=port, debug=False)
