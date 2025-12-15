// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *

import host.pipe
import system

main args:
  toit-exe := args[0]

  my-path := system.program-path
  end := my-path.index-of --last "test.toit"
  if end == -1: throw "UNEXPECTED"
  input := "$my-path[..end]input.toit"

  process := pipe.fork
      --create-stdout
      --create-stdin
      toit-exe
      [toit-exe, input]

  to-process := process.stdin
  from-process := process.stdout

  from-process.close

  expect-null from-process.in.read
  to-process.out.write "done"

  process.wait
