// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef RUNTIME_VM_STACK_TRACE_H_
#define RUNTIME_VM_STACK_TRACE_H_

#include <functional>

#include "vm/allocation.h"
#include "vm/flag_list.h"
#include "vm/object.h"
#include "vm/symbols.h"

namespace dart {

// Helper class for finding the closure of the caller.
class CallerClosureFinder {
 public:
  explicit CallerClosureFinder(Zone* zone);

  // Recursively follow any `_FutureListener.result`.
  // If no `result`, then return (bottom) `_FutureListener.callback`
  ClosurePtr GetCallerInFutureImpl(const Object& future_);

  // Get caller closure from _FutureListener.
  // Returns closure found either via the `result` Future, or the `callback`.
  ClosurePtr GetCallerInFutureListener(const Object& future_listener);

  // Find caller closure from an async* function receiver context.
  // Returns either the `onData` or the Future awaiter.
  ClosurePtr FindCallerInAsyncGenClosure(const Context& receiver_context);

  // Find caller closure from a function receiver closure.
  // For async* functions, async functions, `Future.timeout` and `Future.wait`,
  // we can do this by finding and following their awaited Futures.
  ClosurePtr FindCaller(const Closure& receiver_closure);

  // Finds the awaited Future from an async function receiver closure.
  ObjectPtr GetAsyncFuture(const Closure& receiver_closure);

  // Get sdk/lib/async/future_impl.dart:_FutureListener.state.
  intptr_t GetFutureListenerState(const Object& future_listener);

  // Get sdk/lib/async/future_impl.dart:_FutureListener.callback.
  ClosurePtr GetFutureListenerCallback(const Object& future_listener);

  // Get sdk/lib/async/future_impl.dart:_FutureListener.result.
  ObjectPtr GetFutureListenerResult(const Object& future_listener);

  // Get sdk/lib/async/future_impl.dart:_Future._resultOrListeners.
  ObjectPtr GetFutureFutureListener(const Object& future);

  bool HasCatchError(const Object& future_listener);

  static bool IsRunningAsync(const Closure& receiver_closure);

 private:
  ClosurePtr FindCallerInternal(const Closure& receiver_closure);
  ClosurePtr GetCallerInFutureListenerInternal(const Object& future_listener);
  ClosurePtr UnwrapAsyncThen(const Closure& closure);

  Closure& closure_;
  Context& receiver_context_;
  Function& receiver_function_;
  Function& parent_function_;

  Object& context_entry_;
  Object& future_;
  Object& listener_;
  Object& callback_;
  Object& controller_;
  Object& state_;
  Object& var_data_;
  Object& callback_instance_;

  Class& future_impl_class;
  Class& future_listener_class;
  Class& async_start_stream_controller_class;
  Class& stream_controller_class;
  Class& async_stream_controller_class;
  Class& controller_subscription_class;
  Class& buffering_stream_subscription_class;
  Class& stream_iterator_class;
  Function& async_then_wrapper_;

  Field& future_result_or_listeners_field;
  Field& callback_field;
  Field& future_listener_state_field;
  Field& future_listener_result_field;
  Field& controller_controller_field;
  Field& var_data_field;
  Field& state_field;
  Field& on_data_field;
  Field& state_data_field;

  DISALLOW_COPY_AND_ASSIGN(CallerClosureFinder);
};

class StackTraceUtils : public AllStatic {
 public:
  // Find the async_op closure from the stack frame.
  static ClosurePtr FindClosureInFrame(ObjectPtr* last_object_in_caller,
                                       const Function& function);

  static ClosurePtr ClosureFromFrameFunction(
      Zone* zone,
      CallerClosureFinder* caller_closure_finder,
      const DartFrameIterator& frames,
      StackFrame* frame,
      bool* skip_frame,
      bool* is_async);

  static void UnwindAwaiterChain(Zone* zone,
                                 const GrowableObjectArray& code_array,
                                 GrowableArray<uword>* pc_offset_array,
                                 CallerClosureFinder* caller_closure_finder,
                                 const Closure& leaf_closure);

  /// Collects all frames on the current stack until an async/async* frame is
  /// hit which has yielded before (i.e. is not in sync-async case).
  ///
  /// From there on finds the closure of the async/async* frame and starts
  /// traversing the listeners:
  ///     while (closure != null) {
  ///       yield_index = closure.context[Context::kAsyncJumpVarIndex]
  ///       pc = closure.function.code.pc_descriptors.LookupPcFromYieldIndex(
  ///           yield_index);
  ///       <emit pc in frame>
  ///       closure = closure.context[Context::kAsyncCompleterVarIndex]._future
  ///           ._resultOrListeners.callback;
  ///     }
  ///
  /// If [on_sync_frames] is non-nullptr, it will be called for every
  /// synchronous frame which is collected.
  static void CollectFramesLazy(
      Thread* thread,
      const GrowableObjectArray& code_array,
      GrowableArray<uword>* pc_offset_array,
      int skip_frames,
      std::function<void(StackFrame*)>* on_sync_frames = nullptr,
      bool* has_async = nullptr);

  /// Counts the number of stack frames.
  /// Skips over the first |skip_frames|.
  /// If |async_function| is not null, stops at the function that has
  /// |async_function| as its parent, and records in 'sync_async_end' whether
  /// |async_function| was called synchronously.
  static intptr_t CountFrames(Thread* thread,
                              int skip_frames,
                              const Function& async_function,
                              bool* sync_async_end);

  /// Collects |count| frames into |code_array| and |pc_offset_array|.
  /// Writing begins at |array_offset|.
  /// Skips over the first |skip_frames|.
  /// Returns the number of frames collected.
  static intptr_t CollectFrames(Thread* thread,
                                const Array& code_array,
                                const TypedData& pc_offset_array,
                                intptr_t array_offset,
                                intptr_t count,
                                int skip_frames);
};

}  // namespace dart

#endif  // RUNTIME_VM_STACK_TRACE_H_
