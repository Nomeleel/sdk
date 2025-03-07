// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// @dart = 2.7

import 'package:compiler/src/util/testing.dart';

/*class: A:deps=[method2],direct,explicit=[A.T*],needsArgs*/
class A<T> {
  @pragma('dart2js:noInline')
  foo(x) {
    return x is T;
  }
}

/*class: BB:implicit=[BB]*/
class BB {}

/*member: method2:deps=[B],implicit=[method2.T],indirect,needsArgs*/
@pragma('dart2js:noInline')
method2<T>() => new A<T>();

/*class: B:implicit=[B.T],indirect,needsArgs*/
class B<T> implements BB {
  @pragma('dart2js:noInline')
  foo() {
    return method2<T>().foo(new B());
  }
}

main() {
  makeLive(new B<BB>().foo());
  makeLive(new B<String>().foo());
}
