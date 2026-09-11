"""A flask application with a JSON health check endpoint."""

import logging
import socket
import time

from flask import Flask, jsonify, request

app = Flask(__name__)

logging.basicConfig(
    filename="/var/log/myapp/app.log",
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("myapp")
_START = time.monotonic()


@app.before_request
def log_request():
    log.info("%s %s from %s", request.method, request.path, request.remote_addr)


@app.get("/")
def index():
    return jsonify(
        service="myapp",
        version="1.0.0",
        hostname=socket.gethostname(),
        message="Hello this is from the backend!",
    )


@app.get("/health")
def health():
    return jsonify(
        status="ok",
        service="myapp",
        hostname=socket.gethostname(),
        uptime_seconds=int(time.monotonic() - _START),
    ), 200


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=3000)