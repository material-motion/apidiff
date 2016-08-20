#!/usr/bin/env python

import os
import re
import subprocess
import sys
from collections import namedtuple
from collections import defaultdict

# Note: The components of SymbolId should be chosen such that if two SymbolIds
# are not equal, then they should represent two legal symbols.
#
# One consequence of this rule is that you cannot have a separate
# Kind.Klass vs Kind.Interface since that could represent
# class Foo and interface Foo, which would be a name conflict.
SymbolId = namedtuple('SymbolId', 'klass kind signature')

# Full definition is the entire public api with all decorations.
# Short definition is usually the signature, plus useful human-useful
# identifiers like the method return type, field type, or @ for annotations.
Definition = namedtuple('Definition', 'full short kind_description')

class Kind:
  KLASS, CONSTRUCTOR, FIELD, METHOD = range(1, 5)

Addition = namedtuple('Addition', 'symbol_id definition')
Deletion = namedtuple('Deletion', 'symbol_id definition')
Modification = namedtuple('Modification', 'symbol_id old_definition new_definition')


def print_api_diff(temp_folder, old_path, new_path):
  '''Prints the diff between old_path and new_path in markdown format.

      old_path, new_path:
          A directory containing one file for each public class.
          Each file contains the public APIs of that class.

      temp_folder:
          The shared parent directory betwen old_path and new_path.
  '''

  old_symbols = _symbols_for_library(old_path)
  new_symbols = _symbols_for_library(new_path)
  report = _changes(old_symbols, new_symbols)
  _print_markdown(report)

def _symbols_for_library(path):
  '''Parses the library directory and returns a map of SymbolId to Definition.

  Input library path contains:
      path
       +-- Klass1
       +-- Klass2
       +-- Klass3
  '''

  symbols = {} # { SymbolId: Definition, ... }
  for directory, subdirectories, files in os.walk(path):
    for file in files:
      symbols.update(_symbols_for_klass(os.path.join(directory, file)))
  return symbols


def _symbols_for_klass(file):
  '''Parses the class file and returns a map of SymbolId to Definition.

  Input class file contains:
      public class Klass1 {
        public constructor();
        public void method(args) throws Exception;
        public int FIELD;
      }
  '''

  symbols = {} # { SymbolId: Definition, ... }
  klass = None
  with open(file) as f:
    lines = f.readlines()
    for index, line in enumerate(lines):
      if index == len(lines) - 1:
        # Class declaration end braces.
        continue

      full_definition = line.strip()[:-1].strip()
      (kind, signature, short_definition, kind_description) = _parse_full_definition(full_definition)
      if index == 0:
        # Class declaration.
        klass = signature

      symbols[SymbolId(klass, kind, signature)] = Definition(full_definition, short_definition, kind_description)
  return symbols


def _parse_full_definition(full_definition):
  '''Parses a symbol's full definition string and returns the (kind, signature, short_definition).'''

  modifiers = '(?:public\s+|protected\s+|private\s+|static\s+|abstract\s+|final\s+|native\s+|strictfp\s+|synchronized\s+|transient\s+|volatile\s+)+'
  klass_type = '(?:class|interface|enum)'
  object_type = '.+?\s+' # Either the return value type or field type.
  throws = '.*'
  extends_implements = '.*'

  # Klass
  match = re.match('%s(%s)\s+(\S+)(%s)' % (modifiers, klass_type, extends_implements), full_definition)
  if match:
    kind_description = match.group(1)
    signature = short_definition = match.group(2)

    # Special processing for annotations.
    extends = match.group(3)
    if kind_description == 'interface' and extends == ' extends java.lang.annotation.Annotation':
      kind_description = 'annotation'
      short_definition = '@%s' % signature

    return (Kind.KLASS, signature, short_definition, kind_description)

  # Method
  match = re.match('%s(%s(\S+\(.*\)))%s' % (modifiers, object_type, throws), full_definition)
  if match:
    signature = match.group(2)
    short_definition = match.group(1)
    return (Kind.METHOD, signature, short_definition, 'method')

  # Constructor
  match = re.match('%s(\S+\(.*\))%s' % (modifiers, throws), full_definition)
  if match:
    signature = short_definition = match.group(1)
    return (Kind.CONSTRUCTOR, signature, short_definition, 'constructor')

  # Field
  match = re.match('%s(%s(\S+))' % (modifiers, object_type), full_definition)
  if match:
    signature = match.group(2)
    short_definition = match.group(1)
    return (Kind.FIELD, signature, short_definition, 'field')

  raise Exception('Could not parse %s' % full_definition)


def _changes(old_symbols, new_symbols):
  '''Groups the two maps of symbols by additions, deletions, and modifications, and returns a map of klass to changes.'''

  changes = defaultdict(list) # {Klass: [Modification, Modification, ...], ...}

  old = set(old_symbols.keys())
  new = set(new_symbols.keys())

  added = [symbol_id for symbol_id in new if symbol_id not in old]
  deleted = [symbol_id for symbol_id in old if symbol_id not in new]
  persisted = [symbol_id for symbol_id in old if symbol_id in new]

  # Additions
  for symbol_id in sorted(added):
    definition = new_symbols[symbol_id]
    changes[symbol_id.klass].append(Addition(symbol_id, definition))

  # Deletions
  for symbol_id in sorted(deleted):
    definition = old_symbols[symbol_id]
    changes[symbol_id.klass].append(Deletion(symbol_id, definition))

  # Modifications
  for symbol_id in sorted(persisted):
    old_definition = old_symbols[symbol_id]
    new_definition = new_symbols[symbol_id]
    if old_definition.full != new_definition.full:
      changes[symbol_id.klass].append(Modification(symbol_id, old_definition, new_definition))

  return changes


def _print_markdown(report):
  '''Prints the report in markdown format.'''

  for (klass, changes) in sorted(report.iteritems()):
    print('## %s' % _simplify(klass))
    print('')
    print('\n\n'.join([_markdown_for_change(change) for change in changes]))
    print('')
    print('')


def _markdown_for_change(change):
  if isinstance(change, Addition):
    return '*new* %s: %s' % (_markdown_for_kind(change), _markdown_for_short_definition(change))
  elif isinstance(change, Deletion):
    return '*removed* %s: %s' % (_markdown_for_kind(change), _markdown_for_short_definition(change))
  elif isinstance(change, Modification):
    return '\n'.join([
      '*modified* %s: %s' % (_markdown_for_kind(change), _markdown_for_short_definition(change)),
      '',
      '| From: | %s |' % _markdown_for_old_full_definition(change),
      '| To: | %s |' % _markdown_for_new_full_definition(change)
    ])
  raise Exception('Could not produce markdown for %s' % change)


def _markdown_for_kind(change):
  return change.definition.kind_description


def _markdown_for_short_definition(change):
  return '`%s`' % _simplify(change.definition.short)


def _markdown_for_old_full_definition(change):
  return _simplify(change.old_definition.full)


def _markdown_for_new_full_definition(change):
  return _simplify(change.new_definition.full)


def _simplify(string):
  '''Replaces all full class names with simple class names.

  Input:
      public com.google.android.material.motion.runtime.Performer$PerformerInstantiationException(java.lang.Class<? extends com.google.android.material.motion.runtime.Performer>, java.lang.Exception)

  Returns:
      public PerformerInstantiationException(Class<? extends Performer>, Exception)
  '''

  boundaries = r'(\(|\)|\s|<|>|,|@)'
  return ''.join([_simplify_token(token) for token in re.split(boundaries, string)])


def _simplify_token(token):
  delimiters = '.', '$'
  for delimiter in delimiters:
    token = token[token.rfind(delimiter)+1:]
  return token


if __name__ == '__main__':
  if len(sys.argv) != 4:
    print('Usage: %s <temp_folder> <old_path> <new_path>' % sys.argv[0])
    sys.exit(1)
  print_api_diff(sys.argv[1], sys.argv[2], sys.argv[3])
