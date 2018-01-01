/// AnyPass.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Foundation

struct AnyPass<Input,Output> {
  fileprivate let _base: _AnyPassBase<Input, Output>

  var base: Any {
    return _base.base
  }

  init<Pass>(_ pass: Pass)
    where Pass: PassProtocol, Pass.Input == Input, Pass.Output == Output
  {
    _base = _AnyPass(pass)
  }

}

extension AnyPass: PassProtocol {

  var name: String {
    return _base.name
  }

  func run(_ input: Input, in context: PassContext) -> Output? {
    return _base.run(input, in: context)
  }

  func composed<Before: PassProtocol>(before that: Before)
    -> AnyPass<Input,Before.Output> where Output == Before.Input
  {
    return _base.composed(before: that)
  }

  func composed<After: PassProtocol>(after that: After)
    -> AnyPass<After.Input,Output> where Input == After.Output
  {
    return that.composed(before: _base)
  }

}

private class _AnyPassBase<Input, Output>: PassProtocol {

  open var base: Any {
    fatalError()
  }

  open var name: String {
    fatalError()
  }

  open func run(_ input: Input, in context: PassContext) -> Output? {
    fatalError()
  }

  open func composed<Before: PassProtocol>(before that: Before)
    -> AnyPass<Input,Before.Output> where Output == Before.Input
  {
    fatalError()
  }

  open func composed<After: PassProtocol>(after that: After)
    -> AnyPass<After.Input,Output> where Input == After.Output
  {
    fatalError()
  }
}

private final class _AnyPass<Base: PassProtocol>
  : _AnyPassBase<Base.Input, Base.Output>
{
  private let _base: Base

  public override var base: Any {
    return _base
  }

  public override var name: String {
    return _base.name
  }

  public init(_ base: Base) {
    self._base = base
  }

  public override func run(_ input: Input, in context: PassContext) -> Output? {
    return _base.run(input, in: context)
  }

  public override func composed<Before: PassProtocol>(before that: Before)
    -> AnyPass<Input,Before.Output> where Output == Before.Input
  {
    return _base.composed(before: that)
  }

  public override func composed<After: PassProtocol>(after that: After)
    -> AnyPass<After.Input,Output> where Input == After.Output
  {
    return _base.composed(after: that)
  }
}
