// Copyright (C) 2022 Toitware ApS. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.

import system

/**
A library to parse command line arguments.

Deprecated. Use the toitlang/pkg-cli package instead.
*/

/// Used as an argument for the `--max` option.
UNLIMITED ::= -1

/**
A customizable parser of command line arguments.
*/
class ArgumentParser:

  /**
  Deprecated. The ArgumentParser class is deprecated. Use the toitlang/pkg-cli package instead.
  */
  constructor:

  // Just so we can instantiate this class without a deprecation warning.
  constructor.private_:

  static calculate-minimum_ rest-names/List? -> int:
    if rest-names == null:
      return 0
    size := rest-names.size
    if size > 0 and rest-names[size - 1] == "...":
      size--
    while size > 0 and rest-names[size - 1].starts-with "[" and rest-names[size - 1].ends-with "]":
      size--
    return size

  static calculate-maximum_ rest-names/List? -> int:
    if rest-names == null:
      return UNLIMITED
    size := rest-names.size
    if size > 0 and rest-names[size - 1] == "...":
      return UNLIMITED
    return size

  static calculate-rest-usage_ rest-names/List? rest-minimum/int rest-maximum/int -> string:
    if rest-maximum == 0: return ""

    parts := [""]

    count := max
      rest-maximum == UNLIMITED ? rest-minimum : rest-maximum
      rest-names ? rest-names.size : 0

    count.repeat: | i |
      name := (rest-names and rest-names.size > i) ? rest-names[i] : "argument"
      if name.starts-with "<" and name.ends-with ">":
        parts.add name
      if name.starts-with "[" and name.ends-with "]":
        parts.add name
      else if i >= rest-minimum and name != "...":
        parts.add "[$name]"
      else if name != "...":
        parts.add "<$name>"

    if rest-maximum == UNLIMITED:
      parts.add "..."

    return parts.join " "

  /**
  Add a new command to the parser.
  Returns a new $ArgumentParser for the given command.
  */
  add-command name/string -> ArgumentParser:
    if rest-was-described_: throw "Can't have rest arguments and commands"
    // TODO(kasper): Check if we already have a parser for the given
    // command name. Don't allow duplicates.
    return commands_[name] = ArgumentParser.private_

  /// Adds a boolean flag for the given name. Always defaults to false. Can be
  ///   set to true by passing '--<name>' or '-<short>' if short isn't null.
  add-flag name/string --short/string?=null -> none:
    options_["--$name"] = Option_ name --is-flag --default=false
    if short: add-alias name short

  /// Adds an option with the given default value.
  add-option name/string --default=null --short/string?=null -> none:
    options_["--$name"] = Option_ name --default=default
    if short: add-alias name short

  /// Adds an option that can be provided multiple times.
  add-multi-option name/string --split-commas/bool=true --short/string?=null -> none:
    options_["--$name"] = Option_ name --is-multi-option --split-commas=split-commas
    if short: add-alias name short

  /// Adds a short alias for an option.
  add-alias name/string short/string:
    options_["-$short"] = options_["--$name"]

  /**
  Provides a list of arguments that can be provided after the options.  This
    list will be used for usage messages.
  $min specifies the minimum number of arguments that must be provided
    after the options.  It defaults to the length of the $names list, or
    zero.  When using the length of the $names to determine default
    $min, trailing arguments that are surrounded by "[]" are not counted, nor
    are trailing arguments that are named "...".
  $max specifies the maximum number of arguments that must be provided
    after the options.  It defaults to the length of the $names list, or
    $UNLIMITED if the last member of the $names list is "...".
  $usage is a textual description of the rest arguments that can be
    provided.  It defaults to a string constructed from the other arguments.
  */
  describe-rest -> none
      names /List? = null
      --min /int = (calculate-minimum_ names)
      --max /int = (calculate-maximum_ names)
      --usage /string? = (calculate-rest-usage_ names min max):
    if commands_.size != 0: throw "Can't have rest arguments and commands"
    rest-minimum = min
    rest-maximum = max
    rest-usage = usage
    rest-was-described_ = true

  /**
  Parses the given $arguments.
  If there is an error it prints the error message and the usage
    description on stderr, then exits the VM completely with a non-zero
    exit value.
  The $invoked-command is used only for the usage message in case of an
    error.  It defaults to $system.program-name.
  */
  parse arguments --invoked-command=system.program-name -> Arguments:
    return parse arguments --invoked-command=invoked-command: | error-message usage-string |
      print-on-stderr_ "$error-message"
      print-on-stderr_
          usage-string
      exit 1

  /**
  Parses the given $arguments.
  If there is an error in the arguments the block will be called.  If the block
    returns, an exception is thrown.  The arguments to the block are:
  `error_message`: the error message.
  `usage_string`: A usage string for the whole parser, or perhaps just the subcommand the user attempted to use.
    This may be a multiline string, but it doesn't have a terminating newline.
  The $invoked-command is used only for the usage message in case of an
    error.  It defaults to $system.program-name.
  */
  parse arguments --invoked-command=system.program-name [error-block] -> Arguments:
    try:
      return parse_ this null arguments 0
    finally: | is-exception exception |
      if is-exception:
        (arguments.size + 1).repeat:
          if it >= arguments.size or not arguments[it].starts-with "-":
            error-block.call exception.value (usage arguments[it..] --invoked-command=invoked-command)

  commands_ := {:}
  options_ := {:}
  rest-minimum/int := 0
  rest-maximum/int := UNLIMITED
  rest-usage/string := ""
  rest-was-described_/bool := false

  /**
  Provides a usage guide for the user.  The arguments list is
    used to limit usage to a subcommand if any.
  The $invoked-command is used only for the usage message in case of an
    error.  It defaults to $system.program-name.
  */
  usage arguments/List=[] --invoked-command=system.program-name -> string:
    result := "Usage:"
    prefix := "$invoked-command "
    parser := this
    for index := 0; index < arguments.size; index++:
      command := arguments[index]
      if parser.commands_.contains command:
        if parser.options_.size != 0:
          // When giving usage for a subcommand we don't specify all the
          // options of the super-command.
          prefix += "[options] "
        prefix += command + " "
        parser = commands_[command]
      else if parser.options_.contains command:
        if (command.index-of "=") == -1 and not parser.options_[command].is-flag and parser.options_[command].default == null:
          index++  // Skip the option's argument.
        continue
      else:
        break
    return "Usage:" + (parser.usage_ --prefix=prefix)

  usage_ --prefix -> string:
    options_.do: | name option |
      if name.starts-with "--":
        display-name := name
        options_.do: | shortname shortoption |
          if shortname != name and shortoption == option:
            display-name = "$shortname|$display-name"
        if option.is-flag:
          prefix = "$(prefix)[$display-name] "
        else:
          star := option.is-multi-option ? "*" : ""
          prefix = "$(prefix)[$display-name=<$name[2..]>]$star "
    if commands_.is-empty:
      if rest-usage != "":
        return "\n$(prefix)[--]$rest-usage"
      return "\n$prefix[..prefix.size - 1]"
    result := ""
    commands_.do: | command subparser |
      result += subparser.usage_ --prefix="$prefix$command "
    return result

class Arguments:
  constructor .command_:
  constructor .command_ .options_ .rest_:

  /// Returns the parsed command or null.
  command -> string?:
    return command_

  // Returns the parsed option or the default value.
  operator[] key/string -> any:
    return options_.get key --if-absent=: throw "No option named '$key'"

  // Returns the non-option arguments.
  rest -> List:
    return rest_

  stringify:
    buffer := []
    if command_: buffer.add command_
    options_.do: | name value | buffer.add "--$name=$value"
    if not rest_.is-empty:
      buffer.add "--"
      rest_.do: buffer.add it
    return buffer.join " "

  command_ := ?
  options_ := {:}
  rest_ := []

// ----------------------------------------------------------------------------

// Argument parsing functionality.
parse_ grammar/ArgumentParser command/string? arguments/List index/int --options={:}:
  // Populate the options from the default values or empty lists (for multi-options)
  rest := []
  grammar.options_.do --values: | option |
    options.get option.name --init=:
      option.is-multi-option ? [] : option.default

  seen-options := {}

  while index < arguments.size:
    argument := arguments[index]

    if not command and rest.size == 0 and index < arguments.size:
      grammar.commands_.get argument --if-present=: | sub |
        return parse_ sub argument arguments index + 1 --options=options

    if argument == "--":
      for i := index + 1; i < arguments.size; i++: rest.add arguments[i]
      break  // We're done!

    option := null
    value := null
    if argument.starts-with "--":
      // Get the option name.
      split := argument.index-of "="
      name := (split < 0) ? argument : argument.copy 0 split

      option = grammar.options_.get name --if-absent=: throw "Unknown option $name"
      if split >= 0: value = argument.copy split + 1
    else if argument.starts-with "-":
      // Compute the option and the effective name. We allow short form prefixes to have
      // the value encoded in the same argument like -s"123 + 345", so we have to search
      // for prefixes.
      name := argument
      grammar.options_.get argument
        --if-present=:
          name = argument
          option = it
        --if-absent=:
          grammar.options_.do --keys:
            if argument.starts-with it:
              name = it
              option = grammar.options_[it]
      if not option: throw "Unknown option $argument"

      if name != argument:
        value = argument.copy name.size

    if option:
      if option.is-flag:
        if value: throw "Cannot specify value for boolean flags ($value)"
        value = true
      else if not value:
        if ++index >= arguments.size: throw "No value provided for option $argument"
        value = arguments[index]

      if option.is-multi-option:
        values := option.split-commas ? value.split "," : [value]
        options[option.name].add-all values
      else if seen-options.contains option.name:
        throw "Option was provided multiple times: $argument"
      else:
        options[option.name] = value
        seen-options.add option.name
    else:
      rest.add argument
    index++

  if rest.size < grammar.rest-minimum:
    throw "Too few arguments"

  if grammar.rest-maximum != UNLIMITED and rest.size > grammar.rest-maximum:
    throw "Too many arguments"

  // Construct an [Arguments] object and return it.
  return Arguments command options rest

class Option_:
  name := ?
  is-flag := false
  is-multi-option := false
  split-commas := false  // Only used, if this is a multi-option.
  default := ?

  constructor .name --.is-flag=false --.is-multi-option=false --.split-commas=false --.default=null:
    assert: not split-commas or is-multi-option
