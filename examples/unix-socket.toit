// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import monitor show Latch

import ..src.directory as directory
import ..src.file as file
import ..src.unix-socket as unix

// Runs a one-connection echo server and client in separate tasks.
main:
  tmp := directory.mkdtemp "/tmp/toit-echo-"
  path := "$tmp/socket"
  server := null
  try:
    server = unix.listen path
    done := Latch
    task::
      error := catch:
        peer := server.accept
        try:
          peer.out.write peer.in.read-all.to-string
          peer.out.close
        finally:
          peer.close
      done.set error
    client := unix.connect path
    try:
      client.out.write "Hello over a Unix socket!"
      client.out.close
      print client.in.read-all.to-string
      error := done.get
      if error: throw error
    finally:
      client.close
  finally:
    if server:
      server.close
      file.delete path
    directory.rmdir tmp
