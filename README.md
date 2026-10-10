# Host

Host libraries for the Toit platform.

These libraries don't run on the ESP32 and are only useful on desktop machines.

## Unix domain sockets

`host.unix-socket` provides filesystem-addressed stream sockets on Linux and
macOS/BSD.

```toit
import host.unix-socket as unix

main:
  socket := unix.connect "/tmp/my-service/socket"
  try:
    socket.out.write "request"
    socket.out.close  // Finish the request, while continuing to read.
    print socket.in.read-all.to-string
  finally:
    socket.close
```

Use `unix.listen path --backlog=10` to create a listener and `server.accept` to
wait for a connection. Connected sockets expose `in` and `out` streams,
`local-path`, `peer-path`, and `close`. Unnamed endpoints have a null path.
Path queries throw `ILLEGAL_UTF_8` for non-UTF-8 pathnames supplied by external
peers; the connection remains usable.
Closing `out` sends EOF to the peer while leaving `in` usable. Closing the
socket interrupts pending reads and writes; closing the listener interrupts
pending accepts. Repeated `close` calls are harmless.

The application owns the socket pathname: listening fails if it already exists,
and closing does not delete it. Use a private directory and clean up explicitly
with `host.file.delete` and `host.directory.rmdir`. Permissions follow the host
OS and umask. Path limits apply to encoded bytes, including the terminating NUL;
empty paths and embedded NULs are rejected. Relative paths use the Toit process
current directory and are resolved to absolute paths before connecting or
listening. Abstract addresses, datagrams,
descriptor passing, and peer credentials are not supported.

[The echo example](examples/unix-socket.toit) runs a client and server in separate
tasks and demonstrates temporary-directory cleanup:

```sh
toit run examples/unix-socket.toit
```

The ordinary test suite includes Unix socket behavior tests on Unix hosts.
When Python 3 is available, CTest also checks interoperability with Python
sockets in both directions. Run that check directly with:

```sh
python3 tests/unix_socket_interop.py /path/to/toit
```
