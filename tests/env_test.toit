// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import host.pipe
import host.os
import host.file

main args:
  if args.size < 2:
    print "Usage: echo.toit <something> <toit_exe>"
    exit 1

  if not file.is_file "echo.toit":
    print "Cannot find toit file 'echo.toit' in current directory"
    exit 1

  toit_exe := args[1]

  if not file.is_file toit_exe:
    print "Cannot find toit executable '$toit_exe'"
    exit 1

  pipe.system "$toit_exe echo.toit FOO=\$FOO"
  pipe.system --environment={"FOO": 123} "$toit_exe echo.toit FOO=\$FOO"

  shell := platform == "Windows" ? ["cmd", "/S", "/C"] : ["sh", "-c"]

  expect_equals "BAR=1.5"
      (pipe.backticks --environment={"BAR": 1.5} toit_exe "echo.toit" "BAR=\$BAR").trim
  expect_equals "BAR="
      (pipe.backticks shell + ["$toit_exe echo.toit BAR=\$BAR"]).trim

  fd := pipe.from --environment={"FISH": "HORSE"} toit_exe "echo.toit" "\$FISH"
  expect_equals "HORSE" fd.read.to_string.trim

  user := os.env.get "USER"
  if user:
    expect_equals "$user"
      (pipe.backticks shell + ["$toit_exe echo.toit \$USER"]).trim
    user_fd := pipe.from --environment={"USER": null} toit_exe "echo.toit" "\$USER"
    expect_equals "" user_fd.read.to_string.trim
