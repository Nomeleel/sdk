// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart2js.universe.world_impact;

import '../elements/entities.dart';
import '../util/util.dart' show Setlet;
import 'use.dart';

/// Describes how an element (e.g. a method) impacts the closed-world
/// semantics of a program.
///
/// A [WorldImpact] contains information about how a program element affects our
/// understanding of what's live in a program. For example, it can indicate
/// that a method uses a certain feature, or allocates a specific type.
///
/// The impact object can be computed locally by inspecting just the resolution
/// information of that element alone. The compiler uses [Universe] and
/// [World] to combine the information discovered in the impact objects of
/// all elements reachable in an application.
class WorldImpact {
  const WorldImpact();

  MemberEntity get member => null;

  Iterable<DynamicUse> get dynamicUses => const [];

  Iterable<StaticUse> get staticUses => const [];

  // TODO(johnniwinther): Replace this by called constructors with type
  // arguments.
  // TODO(johnniwinther): Collect all checked types for checked mode separately
  // to support serialization.

  Iterable<TypeUse> get typeUses => const [];

  Iterable<ConstantUse> get constantUses => const [];

  bool get isEmpty => true;

  void apply(WorldImpactVisitor visitor) {
    staticUses.forEach((StaticUse use) => visitor.visitStaticUse(member, use));
    dynamicUses
        .forEach((DynamicUse use) => visitor.visitDynamicUse(member, use));
    typeUses.forEach((TypeUse use) => visitor.visitTypeUse(member, use));
    constantUses
        .forEach((ConstantUse use) => visitor.visitConstantUse(member, use));
  }

  @override
  String toString() => dump(this);

  static String dump(WorldImpact worldImpact) {
    StringBuffer sb = StringBuffer();
    printOn(sb, worldImpact);
    return sb.toString();
  }

  static void printOn(StringBuffer sb, WorldImpact worldImpact) {
    sb.write('member: ${worldImpact.member}');

    void add(String title, Iterable iterable) {
      if (iterable.isNotEmpty) {
        sb.write('\n $title:');
        iterable.forEach((e) => sb.write('\n  $e'));
      }
    }

    add('dynamic uses', worldImpact.dynamicUses);
    add('static uses', worldImpact.staticUses);
    add('type uses', worldImpact.typeUses);
    add('constant uses', worldImpact.constantUses);
  }
}

abstract class WorldImpactBuilder {
  void registerDynamicUse(DynamicUse dynamicUse);
  void registerTypeUse(TypeUse typeUse);
  void registerStaticUse(StaticUse staticUse);
  void registerConstantUse(ConstantUse constantUse);
}

class WorldImpactBuilderImpl extends WorldImpact implements WorldImpactBuilder {
  // TODO(johnniwinther): Do we benefit from lazy initialization of the
  // [Setlet]s?
  Set<DynamicUse> _dynamicUses;
  Set<StaticUse> _staticUses;
  Set<TypeUse> _typeUses;
  Set<ConstantUse> _constantUses;

  WorldImpactBuilderImpl();

  WorldImpactBuilderImpl.internal(
      this._dynamicUses, this._staticUses, this._typeUses, this._constantUses);

  @override
  bool get isEmpty =>
      _dynamicUses == null &&
      _staticUses == null &&
      _typeUses == null &&
      _constantUses == null;

  /// Copy uses in [impact] to this impact builder.
  void addImpact(WorldImpact impact) {
    if (impact.isEmpty) return;
    impact.dynamicUses.forEach(registerDynamicUse);
    impact.staticUses.forEach(registerStaticUse);
    impact.typeUses.forEach(registerTypeUse);
    impact.constantUses.forEach(registerConstantUse);
  }

  @override
  void registerDynamicUse(DynamicUse dynamicUse) {
    assert(dynamicUse != null);
    _dynamicUses ??= Setlet();
    _dynamicUses.add(dynamicUse);
  }

  @override
  Iterable<DynamicUse> get dynamicUses {
    return _dynamicUses ?? const [];
  }

  @override
  void registerTypeUse(TypeUse typeUse) {
    assert(typeUse != null);
    _typeUses ??= Setlet();
    _typeUses.add(typeUse);
  }

  @override
  Iterable<TypeUse> get typeUses {
    return _typeUses ?? const [];
  }

  @override
  void registerStaticUse(StaticUse staticUse) {
    assert(staticUse != null);
    _staticUses ??= Setlet();
    _staticUses.add(staticUse);
  }

  @override
  Iterable<StaticUse> get staticUses {
    return _staticUses ?? const [];
  }

  @override
  void registerConstantUse(ConstantUse constantUse) {
    assert(constantUse != null);
    _constantUses ??= Setlet();
    _constantUses.add(constantUse);
  }

  @override
  Iterable<ConstantUse> get constantUses {
    return _constantUses ?? const [];
  }
}

/// [WorldImpactBuilder] that can create and collect a sequence of
/// [WorldImpact]s.
class StagedWorldImpactBuilder implements WorldImpactBuilder {
  final bool collectImpacts;
  WorldImpactBuilderImpl _currentBuilder;
  final List<WorldImpactBuilderImpl> _builders = [];

  StagedWorldImpactBuilder({this.collectImpacts = false});

  void _ensureBuilder() {
    if (_currentBuilder == null) {
      _currentBuilder = WorldImpactBuilderImpl();
      if (collectImpacts) {
        _builders.add(_currentBuilder);
      }
    }
  }

  @override
  void registerTypeUse(TypeUse typeUse) {
    _ensureBuilder();
    _currentBuilder.registerTypeUse(typeUse);
  }

  @override
  void registerDynamicUse(DynamicUse dynamicUse) {
    _ensureBuilder();
    _currentBuilder.registerDynamicUse(dynamicUse);
  }

  @override
  void registerStaticUse(StaticUse staticUse) {
    _ensureBuilder();
    _currentBuilder.registerStaticUse(staticUse);
  }

  @override
  void registerConstantUse(ConstantUse constantUse) {
    _ensureBuilder();
    _currentBuilder.registerConstantUse(constantUse);
  }

  /// Returns the [WorldImpact] built so far with this builder. The builder
  /// is reset, and if [collectImpacts] is `true` the impact is cached for
  /// [worldImpacts].
  WorldImpact flush() {
    if (_currentBuilder == null) return const WorldImpact();
    WorldImpact worldImpact = _currentBuilder;
    _currentBuilder = null;
    return worldImpact;
  }

  /// If [collectImpacts] is `true` this returns all [WorldImpact]s built with
  /// this builder.
  Iterable<WorldImpact> get worldImpacts => _builders;
}

/// Mutable implementation of [WorldImpact] used to transform
/// [ResolutionImpact] or [CodegenImpact] to [WorldImpact].
class TransformedWorldImpact implements WorldImpact, WorldImpactBuilder {
  final WorldImpact worldImpact;

  Setlet<StaticUse> _staticUses;
  Setlet<TypeUse> _typeUses;
  Setlet<DynamicUse> _dynamicUses;
  Setlet<ConstantUse> _constantUses;

  TransformedWorldImpact(this.worldImpact);

  @override
  MemberEntity get member => worldImpact.member;

  @override
  bool get isEmpty {
    return worldImpact.isEmpty &&
        _staticUses == null &&
        _typeUses == null &&
        _dynamicUses == null &&
        _constantUses == null;
  }

  @override
  Iterable<DynamicUse> get dynamicUses {
    return _dynamicUses ?? worldImpact.dynamicUses;
  }

  @override
  void registerDynamicUse(DynamicUse dynamicUse) {
    _dynamicUses ??= Setlet.of(worldImpact.dynamicUses);
    _dynamicUses.add(dynamicUse);
  }

  @override
  void registerTypeUse(TypeUse typeUse) {
    _typeUses ??= Setlet.of(worldImpact.typeUses);
    _typeUses.add(typeUse);
  }

  @override
  Iterable<TypeUse> get typeUses {
    return _typeUses ?? worldImpact.typeUses;
  }

  @override
  void registerStaticUse(StaticUse staticUse) {
    _staticUses ??= Setlet.of(worldImpact.staticUses);
    _staticUses.add(staticUse);
  }

  @override
  Iterable<StaticUse> get staticUses {
    return _staticUses ?? worldImpact.staticUses;
  }

  @override
  Iterable<ConstantUse> get constantUses {
    return _constantUses ?? worldImpact.constantUses;
  }

  @override
  void registerConstantUse(ConstantUse constantUse) {
    _constantUses ??= Setlet.of(worldImpact.constantUses);
    _constantUses.add(constantUse);
  }

  @override
  void apply(WorldImpactVisitor visitor) {
    staticUses.forEach((StaticUse use) => visitor.visitStaticUse(member, use));
    dynamicUses
        .forEach((DynamicUse use) => visitor.visitDynamicUse(member, use));
    typeUses.forEach((TypeUse use) => visitor.visitTypeUse(member, use));
    constantUses
        .forEach((ConstantUse use) => visitor.visitConstantUse(member, use));
  }

  @override
  String toString() {
    StringBuffer sb = StringBuffer();
    sb.write('TransformedWorldImpact($worldImpact)');
    WorldImpact.printOn(sb, this);
    return sb.toString();
  }
}

/// Visitor used to process the uses of a [WorldImpact].
abstract class WorldImpactVisitor {
  void visitStaticUse(MemberEntity member, StaticUse staticUse);
  void visitDynamicUse(MemberEntity member, DynamicUse dynamicUse);
  void visitTypeUse(MemberEntity member, TypeUse typeUse);
  void visitConstantUse(MemberEntity member, ConstantUse typeUse);
}

// TODO(johnniwinther): Remove these when we get anonymous local classes.
typedef VisitUse<U> = void Function(MemberEntity member, U use);

class WorldImpactVisitorImpl implements WorldImpactVisitor {
  final VisitUse<StaticUse> _visitStaticUse;
  final VisitUse<DynamicUse> _visitDynamicUse;
  final VisitUse<TypeUse> _visitTypeUse;
  final VisitUse<ConstantUse> _visitConstantUse;

  WorldImpactVisitorImpl(
      {VisitUse<StaticUse> visitStaticUse,
      VisitUse<DynamicUse> visitDynamicUse,
      VisitUse<TypeUse> visitTypeUse,
      VisitUse<ConstantUse> visitConstantUse})
      : _visitStaticUse = visitStaticUse,
        _visitDynamicUse = visitDynamicUse,
        _visitTypeUse = visitTypeUse,
        _visitConstantUse = visitConstantUse;

  @override
  void visitStaticUse(MemberEntity member, StaticUse use) {
    if (_visitStaticUse != null) {
      _visitStaticUse(member, use);
    }
  }

  @override
  void visitDynamicUse(MemberEntity member, DynamicUse use) {
    if (_visitDynamicUse != null) {
      _visitDynamicUse(member, use);
    }
  }

  @override
  void visitTypeUse(MemberEntity member, TypeUse use) {
    if (_visitTypeUse != null) {
      _visitTypeUse(member, use);
    }
  }

  @override
  void visitConstantUse(MemberEntity member, ConstantUse use) {
    if (_visitConstantUse != null) {
      _visitConstantUse(member, use);
    }
  }
}
