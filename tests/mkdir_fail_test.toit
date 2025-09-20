// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import expect show *
import system

import host.file
import host.directory show *

with-tmp-dir [block]:
  tmp-dir := mkdtemp "/tmp/mkdir-rmdir-test-"
  try:
    block.call tmp-dir
  finally:
    rmdir --recursive --force tmp-dir

main:
  with-tmp-dir: | tmp-dir |
    mkdir "$tmp-dir/foo"
    expect-throw "ALREADY_EXISTS": mkdir "$tmp-dir/foo"
