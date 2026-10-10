# Copyright (C) 2026 Toit contributors.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/TESTS_LICENSE file.

"""Exercise both directions against an independent Unix socket implementation."""

import pathlib
import selectors
import socket
import subprocess
import sys
import tempfile


def receive_all(connection):
    result = bytearray()
    while True:
        chunk = connection.recv(4096)
        if not chunk:
            return bytes(result)
        result.extend(chunk)


def start(toit, mode, path):
    helper = pathlib.Path(__file__).with_name("unix_socket_interop.toit")
    return subprocess.Popen(
        [toit, "run", str(helper), "--", mode, str(path)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def finish(process):
    try:
        stdout, stderr = process.communicate(timeout=10)
        assert process.returncode == 0, (stdout, stderr)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


def main(toit):
    with tempfile.TemporaryDirectory(prefix="toit-unix-", dir="/tmp") as directory:
        path = pathlib.Path(directory) / "socket"
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
            server.settimeout(10)
            server.bind(str(path))
            server.listen()
            process = start(toit, "client", path)
            try:
                connection, _ = server.accept()
                with connection:
                    connection.settimeout(10)
                    assert receive_all(connection) == b"from-toit"
                    connection.sendall(b"from-python")
                    connection.shutdown(socket.SHUT_WR)
            finally:
                finish(process)
        path.unlink()

        modes = ["server"]
        # Linux permits arbitrary filename bytes; macOS filesystems may not.
        if sys.platform == "linux":
            modes.append("server-invalid-peer")
        for mode in modes:
            process = start(toit, mode, path)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    assert selector.select(timeout=10), "Listener did not become ready"
                    assert process.stdout.readline() == b"ready\n"
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                    connection.settimeout(10)
                    if mode == "server-invalid-peer":
                        connection.bind(bytes(path.with_name("peer-")) + b"\xff")
                    connection.connect(str(path))
                    connection.sendall(b"from-python")
                    connection.shutdown(socket.SHUT_WR)
                    assert receive_all(connection) == b"from-toit"
            finally:
                finish(process)
            assert path.exists(), "Closing the listener must preserve its pathname"
            path.unlink()


if __name__ == "__main__":
    main(sys.argv[1])
