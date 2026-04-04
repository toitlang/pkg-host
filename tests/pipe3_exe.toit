// Copyright (C) 2025 Toit contributors.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/TESTS_LICENSE file.

import host.pipe

main:
  // Just wait for a message.
  pipe.stdin.in.read
