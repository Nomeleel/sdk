// Copyright (c) 2014, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:collection';

import 'package:analysis_server/src/protocol_server.dart' hide Element;
import 'package:analysis_server/src/services/correction/status.dart';
import 'package:analysis_server/src/services/refactoring/refactoring.dart';
import 'package:analysis_server/src/services/search/search_engine.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/src/generated/source.dart';

/// Return a new [SourceReference] instance for the given [match].
SourceReference getSourceReference(SearchMatch match) {
  return SourceReference(match);
}

/// When a [Source] (a file) is used in more than one context, [SearchEngine]
/// will return separate [SearchMatch]s for each context. But in rename
/// refactorings we want to update each [Source] only once.
List<SourceReference> getSourceReferences(List<SearchMatch> matches) {
  var uniqueReferences = HashMap<SourceReference, SourceReference>();
  for (var match in matches) {
    var newReference = getSourceReference(match);
    var oldReference = uniqueReferences[newReference];
    if (oldReference == null) {
      uniqueReferences[newReference] = newReference;
      oldReference = newReference;
    }
  }
  return uniqueReferences.keys.toList();
}

/// Abstract implementation of [Refactoring].
abstract class RefactoringImpl implements Refactoring {
  @override
  final List<String> potentialEditIds = <String>[];

  @override
  Future<RefactoringStatus> checkAllConditions() async {
    var result = RefactoringStatus();
    result.addStatus(await checkInitialConditions());
    if (result.hasFatalError) {
      return result;
    }
    result.addStatus(await checkFinalConditions());
    return result;
  }
}

/// The [SourceRange] in some [Source].
///
/// TODO(scheglov) inline this class as SearchMatch
class SourceReference {
  final SearchMatch _match;

  SourceReference(this._match);

  Element get element => _match.element;

  /// The full path of the file containing the match.
  String get file => _match.file;

  @override
  int get hashCode {
    var hash = file.hashCode;
    hash = ((hash << 16) & 0xFFFFFFFF) + range.hashCode;
    return hash;
  }

  bool get isConstructorTearOff =>
      _match.kind == MatchKind.REFERENCE_BY_CONSTRUCTOR_TEAR_OFF;

  bool get isInvocationByEnumConstantWithoutArguments =>
      _match.kind == MatchKind.INVOCATION_BY_ENUM_CONSTANT_WITHOUT_ARGUMENTS;

  bool get isResolved => _match.isResolved;

  SourceRange get range => _match.sourceRange;

  Source get unitSource => _match.unitSource;

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) {
      return true;
    }
    if (other is SourceReference) {
      return other.file == file && other.range == range;
    }
    return false;
  }

  /// Adds the [SourceEdit] to replace this reference.
  void addEdit(SourceChange change, String newText, {String? id}) {
    var edit = createEdit(newText, id: id);
    doSourceChange_addSourceEdit(change, unitSource, edit);
  }

  /// Returns the [SourceEdit] to replace this reference.
  SourceEdit createEdit(String newText, {String? id}) {
    return newSourceEdit_range(range, newText, id: id);
  }

  @override
  String toString() => '$file@$range';
}
