// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import io
import monitor show Latch Semaphore
import system
import host.directory
import host.file
import host.unix-socket as unix

main:
  if system.platform != system.PLATFORM-LINUX and system.platform != system.PLATFORM-MACOS:
    return
  tmp := directory.mkdtemp "/tmp/toit-unix-"
  try:
    invalid-paths-test tmp
    relative-path-test tmp
    transfer-test "$tmp/écho"
    close-test "$tmp/close"
    peer-close-test "$tmp/peer-close"
    ownership-test "$tmp/owned"
    if system.platform == system.PLATFORM-LINUX:
      backlog-test "$tmp/backlog"
      cleanup-test "$tmp/cleanup"
  finally:
    directory.rmdir tmp --recursive

invalid-paths-test tmp/string:
  ["", "a\u0000b", ("x" * 200), ("é" * 100)].do: | path |
    expect-throw "INVALID_ARGUMENT": unix.listen path
    expect-throw "INVALID_ARGUMENT": unix.connect path
  expect-throw "INVALID_ARGUMENT": unix.listen "$tmp/negative" --backlog=-1
  expect-not-null (catch: unix.connect "$tmp/missing")

relative-path-test tmp/string:
  previous := directory.cwd
  directory.chdir tmp
  try:
    server := unix.listen "relative"
    client := unix.connect "relative"
    peer := server.accept
    try:
      // The resolved prefix may differ on macOS where /tmp is a symlink.
      path := "$(directory.cwd)/relative"
      expect-equals path server.local-path
      expect-equals path client.peer-path
      expect-equals path peer.local-path
    finally:
      peer.close
      client.close
      server.close
      file.delete "relative"
  finally:
    directory.chdir previous

transfer-test path/string:
  server := unix.listen path
  done := Latch
  data := "aé\u0000z" * 200_000
  task::
    error := catch:
      socket := server.accept
      try:
        expect-equals path socket.local-path
        expect-null socket.peer-path
        // Delay reading so the sender must handle backpressure.
        sleep --ms=30
        received := socket.in.read-all.to-string
        expect-equals data.byte-size received.byte-size
        expect (data == received)
        socket.out.write "reply"
        socket.out.close
        socket.out.close
      finally:
        socket.close
    done.set error
  socket := unix.connect path
  try:
    expect-null socket.local-path
    expect-equals path socket.peer-path
    // Exercise chunking for an io.Data that is neither a string nor a ByteArray.
    socket.out.write (CustomData data)
    socket.out.close
    socket.out.close
    expect-equals "reply" socket.in.read-all.to-string
    expect-null socket.in.read
    expect-null done.get
  finally:
    socket.close
    socket.close
    server.close
    server.close
    file.delete path

close-test path/string:
  // Closing a listener interrupts a pending accept.
  server := unix.listen path
  started := Semaphore
  done := Latch
  task::
    started.up
    done.set (catch: server.accept)
  started.down
  sleep --ms=10
  server.close
  expect-equals "ALREADY_CLOSED" done.get
  file.delete path

  server = unix.listen path
  client := unix.connect path
  peer := server.accept
  try:
    // Closing a socket interrupts a pending read.
    done = Latch
    task::
      started.up
      done.set (catch: client.in.read)
    started.down
    sleep --ms=10
    client.close
    expect-equals "ALREADY_CLOSED" done.get
    expect-not-null (catch: client.out.write "closed")
    expect-throw "ALREADY_CLOSED": client.peer-path
  finally:
    client.close
    peer.close
    server.close
    file.delete path

  server = unix.listen path
  client = unix.connect path
  peer = server.accept
  try:
    // The peer never reads, forcing the writer to wait for buffer space.
    done = Latch
    task::
      started.up
      done.set (catch: client.out.write (ByteArray (16 * 1024 * 1024)))
    started.down
    sleep --ms=30
    client.close
    expect-equals "ALREADY_CLOSED" done.get
  finally:
    client.close
    peer.close
    server.close
    file.delete path

peer-close-test path/string:
  server := unix.listen path
  client := unix.connect path
  peer := server.accept
  try:
    peer.close
    expect-null client.in.read
    // A broken pipe must throw, never terminate the VM with SIGPIPE.
    expect-not-null (catch: client.out.write "closed peer")
  finally:
    peer.close
    client.close
    server.close
    file.delete path

cleanup-test path/string:
  // Count descriptors after prior tests have initialized the event source.
  sleep --ms=20
  before := fd-count
  50.repeat:
    expect-not-null (catch: unix.connect path)
    server := unix.listen path
    expect-not-null (catch: unix.listen path)
    client := unix.connect path
    peer := server.accept
    client.close
    peer.close
    server.close
    file.delete path
  // The event thread performs actual descriptor closure asynchronously.
  sleep --ms=20
  expect-equals before fd-count
  // Forgotten sockets must be reclaimed by their finalizers as well.
  10.repeat: abandon-sockets path
  3.repeat:
    system.process-stats --gc
    sleep --ms=20
  expect-equals before fd-count

abandon-sockets path/string:
  server := unix.listen path
  client := unix.connect path
  peer := server.accept
  expect-not-null client
  expect-not-null peer
  file.delete path

fd-count -> int:
  stream := directory.DirectoryStream "/proc/self/fd"
  try:
    count := 0
    while stream.next: count++
    return count
  finally:
    stream.close

ownership-test path/string:
  file.write-contents "keep me" --path=path
  expect-not-null (catch: unix.listen path)
  expect-equals "keep me" (file.read-contents path).to-string
  file.delete path
  server := unix.listen path
  expect-not-null (catch: unix.listen path)
  server.close
  // A stale socket path is never silently replaced.
  expect-not-null (catch: unix.listen path)
  file.delete path
  server = unix.listen path
  server.close
  file.delete path

backlog-test path/string:
  server := unix.listen path --backlog=0
  client := unix.connect path
  try:
    // Linux allows one queued connection for backlog zero.
    // A second connect must fail, not report a false successful connection.
    20.repeat:
      expect-not-null (catch: unix.connect path)
    peer := server.accept
    peer.close
    replacement := unix.connect path
    replacement.close
  finally:
    client.close
    server.close
    file.delete path

class CustomData implements io.Data:
  data_/io.Data
  constructor .data_:
  byte-size -> int: return data_.byte-size
  byte-at index/int -> int: return data_.byte-at index
  byte-slice from/int to/int -> CustomData:
    return CustomData (data_.byte-slice from to)
  write-to-byte-array bytes/ByteArray --at/int from/int to/int -> none:
    data_.write-to-byte-array bytes from to --at=at
