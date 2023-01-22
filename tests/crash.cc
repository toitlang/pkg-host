// Copyright (C) 2023 Toitware ApS.
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the tests/LICENSE file.

#include <signal.h>
#include <stdlib.h>

int main(int argc, char** argv) {
  int signal = atoi(argv[1]);
  raise(signal);
}
