# Copyright (C) 2022 Toitware ApS.
# Use of this source code is governed by a Zero-Clause BSD license that can
# be found in the tests/LICENSE file.

cmake_minimum_required(VERSION 3.23)

# We can't add "NONE" here, as the tests create a "crash" executable.
project(host)

enable_testing()
add_subdirectory(tests)
