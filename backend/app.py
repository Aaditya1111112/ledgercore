"""LedgerCore REST API.

Run:  python app.py   (serves on http://localhost:5000)
All balance changes go through the Oracle LEDGER_PKG package.
"""
import oracledb
from flask import Flask, jsonify
from flask_cors import CORS

from routes import accounts, reports, transactions
from services.db import query_one
from services.errors import ApiError, parse_oracle_error


def create_app():
    app = Flask(__name__)
    CORS(app)

    for module in (accounts, transactions, reports):
        app.register_blueprint(module.bp, url_prefix="/api")

    @app.get("/api/health")
    def health():
        row = query_one("SELECT 'ok' AS db FROM dual")
        return jsonify({"api": "ok", "db": row["db"]})

    @app.errorhandler(ApiError)
    def handle_api_error(err):
        return jsonify({"error": err.message}), err.status

    @app.errorhandler(oracledb.DatabaseError)
    def handle_db_error(err):
        (error_obj,) = err.args
        status, payload = parse_oracle_error(error_obj.code, error_obj.message)
        if status == 500:
            app.logger.error("Oracle error: %s", error_obj.message)
        return jsonify(payload), status

    @app.errorhandler(404)
    def not_found(_):
        return jsonify({"error": "Not found"}), 404

    return app


app = create_app()

if __name__ == "__main__":
    app.run(debug=True, port=5000)
