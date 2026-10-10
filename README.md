# Host

Host libraries for the Toit platform.

These libraries don't run on the ESP32 and are only useful on desktop machines.

## Unix domain sockets

[`host.unix-socket`](src/unix-socket.toit) provides filesystem-addressed stream
sockets on Linux and macOS/BSD. See the library's Toitdoc for usage, pathname
ownership, and stream behavior, and [the echo example](examples/unix-socket.toit)
for a client and server with temporary-directory cleanup.

The ordinary test suite includes Unix socket behavior tests on Unix hosts.
When Python 3 is available, CTest also checks interoperability with Python
sockets in both directions. Run that check directly with:

```sh
python3 tests/unix_socket_interop.py /path/to/toit
```
