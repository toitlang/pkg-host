// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

import expect show *
import host.file
import host.os
import host.pipe

main args:
  internal_test
  external_test args

internal_test:
  expect_equals null (os.env.get "NOT_EXISTING_ENV_VAR")
  expect os.env["PATH"] != ""

  os.env["FIDDLE"] = "FADDLE"
  expect_equals "FADDLE" (os.env["FIDDLE"])

  os.env["HEST"] = "HØST"
  expect_equals "HØST" (os.env["HEST"])

  os.env["HØST"] = "HEST"
  expect_equals "HEST" (os.env["HØST"])

external_test args:
  if args.size < 1:
    print "Usage: env_test.toit <toit_exe>"
    exit 1

  if not file.is_file "tests/echo.toit":
    print "Cannot find toit file 'echo.toit' in tests directory"
    exit 1

  toit_exe := args[0]

  pipe.system "$toit_exe tests/echo.toit FOO=\$FOO"
  pipe.system --environment={"FOO": 123} "$toit_exe tests/echo.toit FOO=\$FOO"

  expect_equals "BAR=1.5"
      (pipe.backticks --environment={"BAR": 1.5} toit_exe "tests/echo.toit" "BAR=\$BAR").trim

  expect_equals "string with \" in it"
      (pipe.backticks toit_exe "tests/echo.toit" "string with \" in it").trim

  expect_equals "string with \\\" in it"
      (pipe.backticks toit_exe "tests/echo.toit" "string with \\\" in it").trim
