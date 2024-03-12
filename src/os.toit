// Copyright (C) 2023 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import system

/**
The environment variables of the system.

Not available on embedded platforms.
*/
// TODO(florian): we should probably have a Map mixin and inherit all its methods.
class EnvironmentVariableMap:
  constructor.private_:

  /**
  Gets the current value of an environment variable.
  It is an error if the key is not a currently defined environment variable.
  */
  operator [] key/string -> string:
    result := get-env_ key
    if not result: throw "ENV NOT FOUND"
    return result

  /**
  Sets the current value of an environment variable.
  Environment variables are inherited by subprocesses, but note
    that when spawning subprocesses you can specify environment variable
    changes that apply only to subprocess.
  If you are running several Toit processes in a single host OS process,
    they currently share environment variables.
  */
  operator []= key/string value/string -> none:
    set-env_ key value

  /**
  Gets the current value of an environment variable.
  Returns null if the key is not a currently defined environment variable.
  */
  get key/string -> string?:
    return get-env_ key

  /**
  Returns true iff the key is an environment variable that is currently defined.
  */
  contains key/string -> bool:
    return (get key) != null

  /**
  Removes an environment variable from the current set of defined variables.
  */
  remove key/string -> none:
    set-env_ key null

/**
A map-like object that represents the environment variables of the current
  process.
*/
env / EnvironmentVariableMap ::= EnvironmentVariableMap.private_

get-env_ key/string -> string?:
  #primitive.core.get-env

set-env_ key/string value/string? -> none:
  #primitive.core.set-env
