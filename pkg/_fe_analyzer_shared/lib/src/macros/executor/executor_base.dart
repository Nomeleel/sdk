// Copyright (c) 2021, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';

import 'package:_fe_analyzer_shared/src/macros/executor/remote_instance.dart';

import '../api.dart';
import '../executor/introspection_impls.dart';
import '../executor/protocol.dart';
import '../executor/serialization.dart';
import '../executor.dart';

/// Base implementation for macro executors which communicate with some external
/// process to run macros.
///
/// Subtypes must extend this class and implement the [close] and [sendResult]
/// apis to handle communication with the external macro program.
abstract class ExternalMacroExecutorBase extends MacroExecutor {
  /// The stream on which we receive messages from the external macro executor.
  final Stream<Object> messageStream;

  /// The mode to use for serialization - must be a `server` variant.
  final SerializationMode serializationMode;

  /// A map of response completers by request id.
  final _responseCompleters = <int, Completer<Response>>{};

  /// We need to know which serialization zone to deserialize objects in, so
  /// that we read them from the correct cache. Each macro execution creates its
  /// own zone which it stores here by ID and then responses are deserialized in
  /// that same zone.
  static final _serializationZones = <int, Zone>{};

  /// Incrementing identifier for the serialization zone ids.
  static int _nextSerializationZoneId = 0;

  ExternalMacroExecutorBase(
      {required this.messageStream, required this.serializationMode}) {
    messageStream.listen((message) {
      withSerializationMode(serializationMode, () {
        Deserializer deserializer = deserializerFactory(message);
        // Every object starts with a zone ID which dictates the zone in which
        // we should deserialize the message.
        deserializer.moveNext();
        int zoneId = deserializer.expectInt();
        Zone zone = _serializationZones[zoneId]!;
        zone.run(() async {
          deserializer.moveNext();
          MessageType messageType =
              MessageType.values[deserializer.expectInt()];
          switch (messageType) {
            case MessageType.response:
              SerializableResponse response =
                  new SerializableResponse.deserialize(deserializer, zoneId);
              Completer<Response>? completer =
                  _responseCompleters.remove(response.requestId);
              if (completer == null) {
                throw new StateError(
                    'Got a response for an unrecognized request id '
                    '${response.requestId}');
              }
              completer.complete(response);
              break;
            case MessageType.resolveTypeRequest:
              ResolveTypeRequest request =
                  new ResolveTypeRequest.deserialize(deserializer, zoneId);
              StaticType instance =
                  await (request.typeResolver.instance as TypeResolver)
                      .resolve(request.typeAnnotationCode);
              SerializableResponse response = new SerializableResponse(
                  response: new RemoteInstanceImpl(
                      id: RemoteInstance.uniqueId,
                      instance: instance,
                      kind: instance is NamedStaticType
                          ? RemoteInstanceKind.namedStaticType
                          : RemoteInstanceKind.staticType),
                  requestId: request.id,
                  responseType: instance is NamedStaticType
                      ? MessageType.namedStaticType
                      : MessageType.staticType,
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.isExactlyTypeRequest:
              IsExactlyTypeRequest request =
                  new IsExactlyTypeRequest.deserialize(deserializer, zoneId);
              StaticType leftType = request.leftType.instance as StaticType;
              StaticType rightType = request.rightType.instance as StaticType;
              SerializableResponse response = new SerializableResponse(
                  response:
                      new BooleanValue(await leftType.isExactly(rightType)),
                  requestId: request.id,
                  responseType: MessageType.boolean,
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.isSubtypeOfRequest:
              IsSubtypeOfRequest request =
                  new IsSubtypeOfRequest.deserialize(deserializer, zoneId);
              StaticType leftType = request.leftType.instance as StaticType;
              StaticType rightType = request.rightType.instance as StaticType;
              SerializableResponse response = new SerializableResponse(
                  response:
                      new BooleanValue(await leftType.isSubtypeOf(rightType)),
                  requestId: request.id,
                  responseType: MessageType.boolean,
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.declarationOfRequest:
              DeclarationOfRequest request =
                  new DeclarationOfRequest.deserialize(deserializer, zoneId);
              TypeDeclarationResolver resolver = request
                  .typeDeclarationResolver.instance as TypeDeclarationResolver;
              SerializableResponse response = new SerializableResponse(
                  requestId: request.id,
                  responseType: MessageType.remoteInstance,
                  response: (await resolver.declarationOf(request.identifier)
                      // TODO: Consider refactoring to avoid the need for this.
                      as TypeDeclarationImpl),
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.constructorsOfRequest:
              ClassIntrospectionRequest request =
                  new ClassIntrospectionRequest.deserialize(
                      deserializer, messageType, zoneId);
              ClassIntrospector classIntrospector =
                  request.classIntrospector.instance as ClassIntrospector;
              SerializableResponse response = new SerializableResponse(
                  requestId: request.id,
                  responseType: MessageType.declarationList,
                  response: new DeclarationList((await classIntrospector
                          .constructorsOf(request.classDeclaration))
                      // TODO: Consider refactoring to avoid the need for this.
                      .cast<ConstructorDeclarationImpl>()),
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.fieldsOfRequest:
              ClassIntrospectionRequest request =
                  new ClassIntrospectionRequest.deserialize(
                      deserializer, messageType, zoneId);
              ClassIntrospector classIntrospector =
                  request.classIntrospector.instance as ClassIntrospector;
              SerializableResponse response = new SerializableResponse(
                  requestId: request.id,
                  responseType: MessageType.declarationList,
                  response: new DeclarationList((await classIntrospector
                          .fieldsOf(request.classDeclaration))
                      // TODO: Consider refactoring to avoid the need for this.
                      .cast<FieldDeclarationImpl>()),
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.interfacesOfRequest:
              ClassIntrospectionRequest request =
                  new ClassIntrospectionRequest.deserialize(
                      deserializer, messageType, zoneId);
              ClassIntrospector classIntrospector =
                  request.classIntrospector.instance as ClassIntrospector;
              SerializableResponse response = new SerializableResponse(
                  requestId: request.id,
                  responseType: MessageType.declarationList,
                  response: new DeclarationList((await classIntrospector
                          .interfacesOf(request.classDeclaration))
                      // TODO: Consider refactoring to avoid the need for this.
                      .cast<ClassDeclarationImpl>()),
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.methodsOfRequest:
              ClassIntrospectionRequest request =
                  new ClassIntrospectionRequest.deserialize(
                      deserializer, messageType, zoneId);
              ClassIntrospector classIntrospector =
                  request.classIntrospector.instance as ClassIntrospector;
              SerializableResponse response = new SerializableResponse(
                  requestId: request.id,
                  responseType: MessageType.declarationList,
                  response: new DeclarationList((await classIntrospector
                          .methodsOf(request.classDeclaration))
                      // TODO: Consider refactoring to avoid the need for this.
                      .cast<MethodDeclarationImpl>()),
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.mixinsOfRequest:
              ClassIntrospectionRequest request =
                  new ClassIntrospectionRequest.deserialize(
                      deserializer, messageType, zoneId);
              ClassIntrospector classIntrospector =
                  request.classIntrospector.instance as ClassIntrospector;
              SerializableResponse response = new SerializableResponse(
                  requestId: request.id,
                  responseType: MessageType.declarationList,
                  response: new DeclarationList((await classIntrospector
                          .mixinsOf(request.classDeclaration))
                      // TODO: Consider refactoring to avoid the need for this.
                      .cast<ClassDeclarationImpl>()),
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            case MessageType.superclassOfRequest:
              ClassIntrospectionRequest request =
                  new ClassIntrospectionRequest.deserialize(
                      deserializer, messageType, zoneId);
              ClassIntrospector classIntrospector =
                  request.classIntrospector.instance as ClassIntrospector;
              SerializableResponse response = new SerializableResponse(
                  requestId: request.id,
                  responseType: MessageType.remoteInstance,
                  response: (await classIntrospector
                          .superclassOf(request.classDeclaration))
                      // TODO: Consider refactoring to avoid the need for this.
                      as ClassDeclarationImpl?,
                  serializationZoneId: zoneId);
              Serializer serializer = serializerFactory();
              response.serialize(serializer);
              sendResult(serializer);
              break;
            default:
              throw new StateError('Unexpected message type $messageType');
          }
        });
      });
    });
  }

  /// These calls are handled by the higher level executor.
  @override
  String buildAugmentationLibrary(Iterable<MacroExecutionResult> macroResults,
          ResolvedIdentifier Function(Identifier) resolveIdentifier) =>
      throw new StateError('Unreachable');

  @override
  Future<MacroExecutionResult> executeDeclarationsPhase(
          MacroInstanceIdentifier macro,
          DeclarationImpl declaration,
          TypeResolver typeResolver,
          ClassIntrospector classIntrospector) =>
      _sendRequest((zoneId) => new ExecuteDeclarationsPhaseRequest(
          macro,
          declaration,
          new RemoteInstanceImpl(
              instance: typeResolver,
              id: RemoteInstance.uniqueId,
              kind: RemoteInstanceKind.typeResolver),
          new RemoteInstanceImpl(
              instance: classIntrospector,
              id: RemoteInstance.uniqueId,
              kind: RemoteInstanceKind.classIntrospector),
          serializationZoneId: zoneId));

  @override
  Future<MacroExecutionResult> executeDefinitionsPhase(
          MacroInstanceIdentifier macro,
          DeclarationImpl declaration,
          TypeResolver typeResolver,
          ClassIntrospector classIntrospector,
          TypeDeclarationResolver typeDeclarationResolver) =>
      _sendRequest((zoneId) => new ExecuteDefinitionsPhaseRequest(
          macro,
          declaration,
          new RemoteInstanceImpl(
              instance: typeResolver,
              id: RemoteInstance.uniqueId,
              kind: RemoteInstanceKind.typeResolver),
          new RemoteInstanceImpl(
              instance: classIntrospector,
              id: RemoteInstance.uniqueId,
              kind: RemoteInstanceKind.classIntrospector),
          new RemoteInstanceImpl(
              instance: typeDeclarationResolver,
              id: RemoteInstance.uniqueId,
              kind: RemoteInstanceKind.typeDeclarationResolver),
          serializationZoneId: zoneId));

  @override
  Future<MacroExecutionResult> executeTypesPhase(
          MacroInstanceIdentifier macro, DeclarationImpl declaration) =>
      _sendRequest((zoneId) => new ExecuteTypesPhaseRequest(macro, declaration,
          serializationZoneId: zoneId));

  @override
  Future<MacroInstanceIdentifier> instantiateMacro(
          MacroClassIdentifier macroClass,
          String constructor,
          Arguments arguments) =>
      _sendRequest((zoneId) => new InstantiateMacroRequest(
          macroClass, constructor, arguments, RemoteInstance.uniqueId,
          serializationZoneId: zoneId));

  /// These calls are handled by the higher level executor.
  @override
  Future<MacroClassIdentifier> loadMacro(Uri library, String name,
          {Uri? precompiledKernelUri}) =>
      throw new StateError(
          'This executor should be wrapped in a MultiMacroExecutor which will '
          'handle load requests.');

  /// Sends [serializer.result] to [sendPort], possibly wrapping it in a
  /// [TransferableTypedData] object.
  void sendResult(Serializer serializer);

  /// Creates a [Request] with a given serialization zone ID, and handles the
  /// response, casting it to the expected type or throwing the error provided.
  Future<T> _sendRequest<T>(Request Function(int) requestFactory) =>
      withSerializationMode(serializationMode, () async {
        int zoneId = _nextSerializationZoneId++;
        _serializationZones[zoneId] = Zone.current;
        Request request = requestFactory(zoneId);
        Serializer serializer = serializerFactory();
        // It is our responsibility to add the zone ID header.
        serializer.addInt(zoneId);
        request.serialize(serializer);
        sendResult(serializer);
        Completer<Response> completer = new Completer<Response>();
        _responseCompleters[request.id] = completer;
        try {
          Response response = await completer.future;
          T? result = response.response as T?;
          if (result != null) return result;
          throw new RemoteException(
              response.error!.toString(), response.stackTrace);
        } finally {
          // Clean up the zone after the request is done.
          _serializationZones.remove(zoneId);
        }
      });
}
