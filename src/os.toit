// Copyright (C) 2020 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

/**
The environment variables of the system.

Not available on embedded platforms.
*/
// TODO(florian): we should probably have a Map mixin and inherit all its methods.
class EnvironmentVariableMap:
  constructor.private_:

  operator [] key/string -> string:
    result := get_env_ key
    if not result: throw "ENV NOT FOUND"
    return result

  get key/string -> string?:
    return get_env_ key

  contains key/string -> bool:
    return (get key) != null

  all -> Map:
    result := {:}
    index := 0
    while true:
      chunk := get_environment_variables_ index
      if not chunk: break
      for i := 0; i < chunk.size; i++:
        str := chunk[i]
        if str == null:
          index += i
          continue
        equals := str.index_of "="
        if equals == -1:
          result[str] = ""
        else:
          result[str[..equals]] = str[equals + 1 ..]
    return result

env / EnvironmentVariableMap ::= EnvironmentVariableMap.private_

get_env_ key/string -> string?:
  #primitive.core.get_env

get_environment_variables_ index/int -> List?:
  #primitive.core.get_environment_variables
