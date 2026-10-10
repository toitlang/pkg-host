// Copyright (C) 2026 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.unix-socket as unix

main args/List:
  mode := args[0]
  path := args[1]
  if mode == "client":
    socket := unix.connect path
    try:
      socket.out.write "from-toit"
      socket.out.close
      expect-equals "from-python" socket.in.read-all.to-string
    finally:
      socket.close
  else:
    server := unix.listen path
    try:
      print "ready"
      socket := server.accept
      try:
        expect-equals "from-python" socket.in.read-all.to-string
        socket.out.write "from-toit"
        socket.out.close
      finally:
        socket.close
    finally:
      server.close
