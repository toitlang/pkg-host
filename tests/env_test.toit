// Copyright (C) 2020 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import host.pipe
import host.os

main:
  pipe.system "echo FOO=\$FOO"
  pipe.system --environment={"FOO": 123} "echo FOO=\$FOO"

  expect_equals "BAR=1.5\n"
      pipe.backticks --environment={"BAR": 1.5} "sh" "-c" "echo BAR=\$BAR"
  expect_equals "BAR=\n"
      pipe.backticks "sh" "-c" "echo BAR=\$BAR"

  fd := pipe.from --environment={"FISH": "HORSE"} "sh" "-c" "echo \$FISH"
  expect_equals "HORSE\n" fd.read.to_string

  user := os.env.get "USER"
  if user:
    expect_equals "$user\n"
      pipe.backticks "sh" "-c" "echo \$USER"
    user_fd := pipe.from --environment={"USER": null} "sh" "-c" "echo \$USER"
    expect_equals "\n" user_fd.read.to_string
