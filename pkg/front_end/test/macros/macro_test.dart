// Copyright (c) 2021, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io' show Directory, Platform;

import 'package:_fe_analyzer_shared/src/macros/api.dart';
import 'package:_fe_analyzer_shared/src/macros/executor.dart';
import 'package:_fe_analyzer_shared/src/macros/executor/serialization.dart';
import 'package:_fe_analyzer_shared/src/testing/features.dart';
import 'package:_fe_analyzer_shared/src/testing/id.dart' show ActualData, Id;
import 'package:_fe_analyzer_shared/src/testing/id_testing.dart';
import 'package:front_end/src/api_prototype/compiler_options.dart';
import 'package:front_end/src/api_prototype/experimental_flags.dart';
import 'package:front_end/src/fasta/builder/class_builder.dart';
import 'package:front_end/src/fasta/builder/library_builder.dart';
import 'package:front_end/src/fasta/builder/member_builder.dart';
import 'package:front_end/src/fasta/kernel/macro.dart';
import 'package:front_end/src/testing/id_testing_helper.dart';
import 'package:front_end/src/testing/id_testing_utils.dart';
import 'package:kernel/ast.dart' hide Arguments;

Future<void> main(List<String> args) async {
  enableMacros = true;

  Directory dataDir =
      new Directory.fromUri(Platform.script.resolve('data/tests'));
  await runTests<Features>(dataDir,
      args: args,
      createUriForFileName: createUriForFileName,
      onFailure: onFailure,
      runTest: runTestFor(const MacroDataComputer(), [new MacroTestConfig()]));
}

class MacroTestConfig extends TestConfig {
  MacroTestConfig()
      : super(cfeMarker, 'cfe',
            explicitExperimentalFlags: {ExperimentalFlag.macros: true},
            packageConfigUri:
                Platform.script.resolve('data/package_config.json'));

  @override
  TestMacroExecutor customizeCompilerOptions(
      CompilerOptions options, TestData testData) {
    TestMacroExecutor macroExecutor = new TestMacroExecutor();
    options.macroExecutorProvider = () async => macroExecutor;
    Uri precompiledPackage =
        Uri.parse('package:precompiled_macro/precompiled_macro.dart');
    options.precompiledMacroUris = {
      new MacroClass(precompiledPackage, 'PrecompiledMacro'): dummyUri,
    };
    return macroExecutor;
  }
}

class MacroDataComputer extends DataComputer<Features> {
  const MacroDataComputer();

  @override
  void computeMemberData(TestResultData testResultData, Member member,
      Map<Id, ActualData<Features>> actualMap,
      {bool? verbose}) {
    member.accept(new MacroDataExtractor(testResultData, actualMap));
  }

  @override
  void computeClassData(TestResultData testResultData, Class cls,
      Map<Id, ActualData<Features>> actualMap,
      {bool? verbose}) {
    new MacroDataExtractor(testResultData, actualMap).computeForClass(cls);
  }

  @override
  void computeLibraryData(TestResultData testResultData, Library library,
      Map<Id, ActualData<Features>> actualMap,
      {bool? verbose}) {
    new MacroDataExtractor(testResultData, actualMap)
        .computeForLibrary(library);
  }

  @override
  bool get supportsErrors => true;

  @override
  Features? computeErrorData(
      TestResultData testResultData, Id id, List<FormattedMessage> errors) {
    Features features = new Features();
    features[Tags.error] = errorsToText(errors, useCodes: true);
    return features;
  }

  @override
  DataInterpreter<Features> get dataValidator =>
      const FeaturesDataInterpreter();
}

class Tags {
  static const String macrosAreAvailable = 'macrosAreAvailable';
  static const String macrosAreApplied = 'macrosAreApplied';
  static const String compilationSequence = 'compilationSequence';
  static const String neededPrecompilations = 'neededPrecompilations';
  static const String declaredMacros = 'declaredMacros';
  static const String appliedMacros = 'appliedMacros';
  static const String macroClassIds = 'macroClassIds';
  static const String macroInstanceIds = 'macroInstanceIds';
  static const String error = 'error';
}

String constructorNameToString(String constructorName) {
  return constructorName == '' ? 'new' : constructorName;
}

String importUriToString(Uri importUri) {
  if (importUri.isScheme('package')) {
    return importUri.toString();
  } else if (importUri.isScheme('dart')) {
    return importUri.toString();
  } else {
    return importUri.pathSegments.last;
  }
}

String libraryToString(Library library) => importUriToString(library.importUri);

String strongComponentToString(Iterable<Uri> uris) {
  List<String> list = uris.map(importUriToString).toList();
  list.sort();
  return list.join('|');
}

class MacroDataExtractor extends CfeDataExtractor<Features> {
  final TestResultData testResultData;

  MacroDataExtractor(
      this.testResultData, Map<Id, ActualData<Features>> actualMap)
      : super(testResultData.compilerResult, actualMap);

  TestMacroExecutor get macroExecutor => testResultData.customData;

  MacroDeclarationData get macroDeclarationData => testResultData.compilerResult
      .kernelTargetForTesting!.loader.dataForTesting!.macroDeclarationData;

  MacroApplicationDataForTesting get macroApplicationData => testResultData
      .compilerResult
      .kernelTargetForTesting!
      .loader
      .dataForTesting!
      .macroApplicationData;

  LibraryMacroApplicationData? getLibraryMacroApplicationData(Library library) {
    for (MapEntry<LibraryBuilder, LibraryMacroApplicationData> entry
        in macroApplicationData.libraryData.entries) {
      if (entry.key.library == library) {
        return entry.value;
      }
    }
    return null;
  }

  ClassMacroApplicationData? getClassMacroApplicationData(Class cls) {
    LibraryMacroApplicationData? applicationData =
        getLibraryMacroApplicationData(cls.enclosingLibrary);
    if (applicationData != null) {
      for (MapEntry<ClassBuilder, ClassMacroApplicationData> entry
          in applicationData.classData.entries) {
        if (entry.key.cls == cls) {
          return entry.value;
        }
      }
    }
    return null;
  }

  List<MacroApplication>? getClassMacroApplications(Class cls) {
    return getClassMacroApplicationData(cls)?.classApplications;
  }

  List<MacroApplication>? getMemberMacroApplications(Member member) {
    Class? enclosingClass = member.enclosingClass;
    Map<MemberBuilder, List<MacroApplication>>? memberApplications;
    if (enclosingClass != null) {
      memberApplications =
          getClassMacroApplicationData(enclosingClass)?.memberApplications;
    } else {
      memberApplications =
          getLibraryMacroApplicationData(member.enclosingLibrary)
              ?.memberApplications;
    }
    if (memberApplications != null) {
      for (MapEntry<MemberBuilder, List<MacroApplication>> entry
          in memberApplications.entries) {
        if (entry.key.member == member) {
          return entry.value;
        }
      }
    }
    return null;
  }

  void registerMacroApplications(
      Features features, List<MacroApplication>? macroApplications) {
    if (macroApplications != null) {
      for (MacroApplication application in macroApplications) {
        String className = application.classBuilder.name;
        String constructorName =
            constructorNameToString(application.constructorName);
        features.addElement(
            Tags.appliedMacros, '${className}.${constructorName}');
      }
    }
  }

  @override
  Features computeClassValue(Id id, Class node) {
    Features features = new Features();
    if (getClassMacroApplicationData(node) != null) {
      features.add(Tags.macrosAreApplied);
    }
    registerMacroApplications(features, getClassMacroApplications(node));
    return features;
  }

  @override
  Features computeLibraryValue(Id id, Library node) {
    Features features = new Features();
    if (macroDeclarationData.macrosAreAvailable) {
      features.add(Tags.macrosAreAvailable);
    }
    if (node == compilerResult.component!.mainMethod!.enclosingLibrary) {
      if (macroDeclarationData.compilationSequence != null) {
        features.markAsUnsorted(Tags.compilationSequence);
        for (List<Uri> component in macroDeclarationData.compilationSequence!) {
          features.addElement(
              Tags.compilationSequence, strongComponentToString(component));
        }
      }
      for (Map<Uri, Map<String, List<String>>> precompilation
          in macroDeclarationData.neededPrecompilations) {
        Map<String, Map<String, List<String>>> converted =
            new Map.fromIterables(precompilation.keys.map(importUriToString),
                precompilation.values);
        List<String> uris = converted.keys.toList()..sort();
        StringBuffer sb = new StringBuffer();
        for (String uri in uris) {
          sb.write(uri);
          sb.write('=');
          Map<String, List<String>> macros = converted[uri]!;
          List<String> classes = macros.keys.toList()..sort();
          String delimiter = '';
          for (String cls in classes) {
            List<String> constructorNames =
                macros[cls]!.map(constructorNameToString).toList()..sort();
            sb.write(delimiter);
            sb.write(cls);
            sb.write('(');
            sb.write(constructorNames.join('/'));
            sb.write(')');
            delimiter = '|';
          }
        }
        features.addElement(Tags.neededPrecompilations, sb.toString());
      }
      for (_MacroClassIdentifier id in macroExecutor.macroClasses) {
        features.addElement(Tags.macroClassIds, id.toText());
      }
      for (_MacroInstanceIdentifier id in macroExecutor.macroInstances) {
        features.addElement(Tags.macroInstanceIds, id.toText());
      }
    }
    List<String>? macroClasses =
        macroDeclarationData.macroDeclarations[node.importUri];
    if (macroClasses != null) {
      for (String clsName in macroClasses) {
        features.addElement(Tags.declaredMacros, clsName);
      }
    }
    if (getLibraryMacroApplicationData(node) != null) {
      features.add(Tags.macrosAreApplied);
    }

    return features;
  }

  @override
  Features computeMemberValue(Id id, Member node) {
    Features features = new Features();
    registerMacroApplications(features, getMemberMacroApplications(node));
    return features;
  }
}

class TestMacroExecutor implements MacroExecutor {
  List<_MacroClassIdentifier> macroClasses = [];
  List<_MacroInstanceIdentifier> macroInstances = [];

  @override
  String buildAugmentationLibrary(Iterable<MacroExecutionResult> macroResults,
      ResolvedIdentifier Function(Identifier) resolveIdentifier) {
    return '';
  }

  @override
  void close() {
    // TODO: implement close
  }

  @override
  Future<MacroExecutionResult> executeDeclarationsPhase(
      MacroInstanceIdentifier macro,
      Declaration declaration,
      TypeResolver typeResolver,
      ClassIntrospector classIntrospector) async {
    return new _MacroExecutionResult();
  }

  @override
  Future<MacroExecutionResult> executeDefinitionsPhase(
      MacroInstanceIdentifier macro,
      Declaration declaration,
      TypeResolver typeResolver,
      ClassIntrospector classIntrospector,
      TypeDeclarationResolver typeDeclarationResolver) async {
    return new _MacroExecutionResult();
  }

  @override
  Future<MacroExecutionResult> executeTypesPhase(
      MacroInstanceIdentifier macro, Declaration declaration) async {
    return new _MacroExecutionResult();
  }

  @override
  Future<MacroInstanceIdentifier> instantiateMacro(
      MacroClassIdentifier macroClass,
      String constructor,
      Arguments arguments) async {
    _MacroInstanceIdentifier id = new _MacroInstanceIdentifier(
        macroClass as _MacroClassIdentifier, constructor, arguments);
    macroInstances.add(id);
    return id;
  }

  @override
  Future<MacroClassIdentifier> loadMacro(Uri library, String name,
      {Uri? precompiledKernelUri}) async {
    _MacroClassIdentifier id = new _MacroClassIdentifier(library, name);
    macroClasses.add(id);
    return id;
  }
}

class _MacroClassIdentifier implements MacroClassIdentifier {
  final Uri uri;
  final String className;

  _MacroClassIdentifier(this.uri, this.className);

  String toText() => '${importUriToString(uri)}/${className}';

  @override
  int get hashCode => uri.hashCode * 13 + className.hashCode * 17;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _MacroClassIdentifier &&
        uri == other.uri &&
        className == other.className;
  }

  @override
  String toString() => 'MacroClassIdentifier($uri,$className)';

  @override
  void serialize(Serializer serializer) => throw UnimplementedError();
}

class _MacroInstanceIdentifier implements MacroInstanceIdentifier {
  final _MacroClassIdentifier macroClass;
  final String constructor;
  final Arguments arguments;

  _MacroInstanceIdentifier(this.macroClass, this.constructor, this.arguments);

  String toText() => '${macroClass.toText()}/${constructor}()';

  @override
  void serialize(Serializer serializer) => throw UnimplementedError();

  @override
  bool shouldExecute(DeclarationKind declarationKind, Phase phase) => false;

  @override
  bool supportsDeclarationKind(DeclarationKind declarationKind) => false;
}

class _MacroExecutionResult implements MacroExecutionResult {
  @override
  Iterable<DeclarationCode> augmentations = const [];

  @override
  Iterable<String> newTypeNames = const [];

  @override
  void serialize(Serializer serializer) {
    throw UnimplementedError();
  }
}
