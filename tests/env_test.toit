// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import host.pipe
import host.os
import host.file
import system show platform PLATFORM-WINDOWS

import .utils

main args:
  if args.size < 1:
    print "Usage: env_test.toit <toit_exe>"
    exit 1

  if not file.is-file "tests/echo.toit":
    print "Cannot find toit file 'echo.toit' in tests directory"
    exit 1

  toit-exe := args[0]

  check-toit-exe toit-exe

  pipe.system "$toit-exe run -- tests/echo.toit FOO=\$FOO"
  pipe.system --environment={"FOO": 123} "$toit-exe run -- tests/echo.toit FOO=\$FOO"

  shell := platform == PLATFORM-WINDOWS ? ["cmd", "/S", "/C"] : ["sh", "-c"]

  expect-equals "BAR=1.5"
      (pipe.backticks --environment={"BAR": 1.5} toit-exe "tests/echo.toit" "BAR=\$BAR").trim
  expect-equals "BAR="
      (pipe.backticks shell + ["$toit-exe run -- tests/echo.toit BAR=\$BAR"]).trim

  fd := pipe.from --environment={"FISH": "HORSE"} toit-exe "tests/echo.toit" "\$FISH"
  expect-equals "HORSE" fd.in.read.to-string.trim

  user := os.env.get "USER"
  if user:
    expect-equals "$user"
      (pipe.backticks shell + ["$toit-exe run -- tests/echo.toit \$USER"]).trim
    user-fd := pipe.from --environment={"USER": null} toit-exe "tests/echo.toit" "\$USER"
    expect-equals "" user-fd.in.read.to-string.trim
