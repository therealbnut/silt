/// TypeChecker.swift
///
/// Copyright 2017, The Silt Language Project.
///
/// This project is released under the MIT license, a copy of which is
/// available in the repository.

import Moho
import Lithosphere

public final class TypeChecker<PhaseState> {
  var state: State<PhaseState>

  final class State<S> {
    fileprivate var signature: Signature
    fileprivate var environment: Environment
    var state: S

    init(_ signature: Signature, _ env: Environment, _ state: S) {
      self.signature = signature
      self.environment = env
      self.state = state
    }
  }

  public convenience init(_ state: PhaseState) {
    self.init(Signature(), Environment([]), state)
  }

  init(_ sig: Signature, _ env: Environment, _ state: PhaseState) {
    self.state = State<PhaseState>(sig, env, state)
  }

  public var signature: Signature {
    return self.state.signature
  }

  public var environment: Environment {
    return self.state.environment
  }
}

extension TypeChecker {
  func underExtendedEnvironment<A>(_ ctx: Context, _ f: () -> A) -> A {
    let oldS = self.environment.context
    self.environment.context.append(contentsOf: ctx)
    let val = f()
    self.environment.context = oldS
    return val
  }

  func extendEnvironment(_ ctx: Context) {
    self.environment.context.append(contentsOf: ctx)
  }

  func underNewScope<A>(_ f: () -> A) -> A {
    let oldBlocks = self.environment.scopes
    let oldPending = self.environment.context
    self.environment.scopes.append(Environment.Scope(self.environment.context, [:]))
    self.environment.context = []
    let result = f()
    self.environment.scopes = oldBlocks
    self.environment.context = oldPending
    return result
  }

  func forEachVariable<T>(in ctx: Context, _ f: (Var) -> T) -> [T] {
    var result = [T]()
    for (ix, (n, _)) in zip((0..<ctx.count).reversed(), ctx).reversed() {
      result.insert(f(Var(n, UInt(ix))), at: 0)
    }
    return result
  }
}

extension TypeChecker {
  func addMeta(
    in ctx: Context, from node: Expr? = nil, expect ty: Type<TT>) -> Term<TT> {
    let metaTy = self.rollPi(in: ctx, final: ty)
    let mv = self.signature.addMeta(metaTy, from: node)
    let metaTm = TT.apply(.meta(mv), [])
    return self.eliminate(metaTm, self.forEachVariable(in: ctx) { v in
      return Elim<TT>.apply(TT.apply(.variable(v), []))
    })
  }
}

extension TypeChecker {
  // Roll a Pi type containing all the types in the context, finishing with the
  // provided type.
  func rollPi(in ctx: Context, final finalTy: Type<TT>) -> Type<TT> {
    var type = finalTy
    for (_, nextTy) in ctx.reversed() {
      type = TT.pi(nextTy, type)
    }
    return type
  }

  // Unroll a Pi type into a telescope of names and types and the final type.
  func unrollPi(
    _ t: Type<TT>, _ ns: [Name]? = nil) -> (Telescope<Type<TT>>, Type<TT>) {
    // FIXME: Try harder, maybe
    let defaultName = Name(name: TokenSyntax(.identifier("_")))
    var tel = Telescope<Type<TT>>()
    var ty = t
    var idx = 0
    while case let .pi(dm, cd) = self.toWeakHeadNormalForm(ty).ignoreBlocking {
      defer { idx += 1 }
      let name = ns?[idx] ?? defaultName
      ty = cd
      tel.append((name, dm))
    }
    return (tel, ty)
  }
}

extension TypeChecker {
  func openContextualDefinition(
      _ ctxt: ContextualDefinition, _ args: [Term<TT>]) -> OpenedDefinition {
    func openAccessor<T>(_ accessor: T) -> Opened<T, TT> {
      return Opened<T, TT>(accessor, args)
    }

    func openConstant(_ c: Definition.Constant) -> OpenedDefinition.Constant {
      switch c {
      case .postulate:
        return .postulate
      case let .data(dataCons):
        return .data(dataCons.map { Opened($0, args) })
      case let .record(name, ps):
        return .record(openAccessor(name), ps.map(openAccessor))
      case let .function(inst):
        return .function(inst)
      }
    }

    precondition(ctxt.telescope.count == args.count)
    switch self.instantiate(ctxt.inside, args) {
    case let .constant(type, constant):
      return .constant(type, openConstant(constant))
    case let .dataConstructor(dataCon, openArgs, type):
      return .dataConstructor(Opened<QualifiedName, TT>(dataCon, args),
                              openArgs, type)
    case let .module(names):
      return .module(names)
    }
  }

  func openDefinition(
    _ name: QualifiedName, _ args: [Term<TT>]) -> Opened<QualifiedName, TT> {
    let e = self.environment
    guard let firstBlock = e.scopes.first, e.context.isEmpty else {
      fatalError()
    }
    firstBlock.opened[name] = args
    e.scopes[0] = Environment.Scope(firstBlock.context, firstBlock.opened)
    e.context = []
    return Opened<QualifiedName, TT>(name, args)
  }

  func getOpenedDefinition(
      _ name: QualifiedName) -> (Opened<QualifiedName, TT>, OpenedDefinition) {
    func getOpenedArguments(_ name: QualifiedName) -> [TT] {
      precondition(!self.environment.scopes.isEmpty)

      var n = self.environment.context.count
      for block in self.environment.scopes {
        if let args = block.opened[name] {
          return args.map { $0.applySubstitution(.weaken(n), self.eliminate) }
        } else {
          n += block.context.count
        }
      }
      fatalError()
    }
    let args = getOpenedArguments(name)
    let contextDef = self.signature.lookupDefinition(name)!
    let def = self.openContextualDefinition(contextDef, args)
    return (Opened<QualifiedName, TT>(name, args), def)
  }

  func getTypeOfOpenedDefinition(_ t: OpenedDefinition) -> Type<TT> {
    switch t {
    case let .constant(ty, _):
      return ty
    case let .dataConstructor(_, _, ct):
      return self.rollPi(in: ct.telescope, final: ct.inside)
    case .module(_):
      fatalError()
    }
  }
}
