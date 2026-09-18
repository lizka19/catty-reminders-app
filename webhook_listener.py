#!/usr/bin/env python3
"""
Webhook-обработчик для автоматического деплоя Catty Reminders App.
Получает push-события от GitHub и выполняет:
  1. git fetch + reset --hard <sha>
  2. запись DEPLOY_REF в /etc/catty-app-env
  3. перезапуск systemd-сервиса catty
"""

import json
import subprocess
import threading
import logging
from http.server import HTTPServer, BaseHTTPRequestHandler

# --- Конфигурация ---
PORT = 8080
APP_DIR = "/home/password_123/Desktop/Catty/catty-reminders-app"
ENV_VARS_FILE = "/etc/catty-app-env"
SERVICE_NAME = "catty"
LOG_FILE = "/home/password_123/webhook-handler/deploy.log"

logging.basicConfig(
    filename=LOG_FILE,
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)


def perform_deployment(commit_hash):
    """Выполняет деплой в отдельном потоке."""
    try:
        subprocess.run(["git", "-C", APP_DIR, "fetch", "--all"], check=True)
        subprocess.run(["git", "-C", APP_DIR, "reset", "--hard", commit_hash], check=True)
        with open(ENV_VARS_FILE, "w") as f:
            f.write(f"DEPLOY_REF={commit_hash}\n")
        subprocess.run(["sudo", "systemctl", "restart", SERVICE_NAME], check=True)
        logging.info(f"Деплой успешен: {commit_hash}")
    except Exception as e:
        logging.error(f"Ошибка деплоя: {e}")


class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length)

        if self.headers.get("X-GitHub-Event") != "push":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"status": "ignored"}')
            return

        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self.send_response(400)
            self.end_headers()
            return

        commit_sha = payload.get("after")
        if commit_sha and commit_sha != "0" * 40:
            threading.Thread(target=perform_deployment, args=(commit_sha,)).start()
            self.send_response(202)
            self.send_header("Content-type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"status": "accepted"}')
        else:
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'{"status": "ignored"}')

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain; charset=utf-8")
        self.end_headers()
        self.wfile.write(b"webhook-handler is running\n")


def main():
    server = HTTPServer(("0.0.0.0", PORT), WebhookHandler)
    logging.info(f"Webhook handler started on port {PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
