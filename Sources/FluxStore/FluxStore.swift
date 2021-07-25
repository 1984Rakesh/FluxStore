
import Foundation
import Combine

public typealias Reducer<State,Action> = (_ state:inout State, _ action: Action) -> [Effect<Action>]

public struct Effect<Output>:Publisher {
    public typealias Output = Output
    public typealias Failure = Never
    let publisher: AnyPublisher<Output,Failure>
    
    
    public func receive<S>(subscriber: S) where S : Subscriber, Never == S.Failure, Output == S.Input {
        self.publisher.receive(subscriber: subscriber)
    }
}

extension Effect {
  public static func sync(work: @escaping () -> Output) -> Effect {
    return Deferred { Just(work()) }
    .eraseToEffect()
  }
}

extension Publisher where Failure == Never {
    public func eraseToEffect() -> Effect<Output> {
        return Effect(publisher: self.eraseToAnyPublisher())
    }
}

public class Store<State,Action>:  ObservableObject {
    @Published public var state: State
    public var reducer: Reducer<State,Action>
    private var effectCancellables: Set<AnyCancellable> = []
    private var viewCancellable: AnyCancellable?
    
    public init(_ state:State, _ reducer:@escaping Reducer<State,Action>){
        self.reducer = reducer
        self.state = state
    }
    
    public func dispatch(_ action: Action) {
        let effects =  self.reducer( &state, action)
        effects.forEach { effect in
            var effectCancellable: AnyCancellable?
            effectCancellable = effect.sink(
                receiveCompletion: { [weak self] _ in
                    guard let effectCancellable = effectCancellable else { return }
                    self?.effectCancellables.remove(effectCancellable)
                },
                receiveValue: { self.dispatch($0) }
            )
            if let cancellable = effectCancellable {
                self.effectCancellables.insert(cancellable)
            }
        }
    }
    
    public func view<LocalState,LocalAction>(
        localState getLocalState:@escaping (State)->LocalState,
        globalAction getGlobalAction:@escaping (LocalAction) -> Action
    ) -> Store<LocalState,LocalAction> {
        let localStore = Store<LocalState,LocalAction>( getLocalState(state)) { localState, localAction in
            self.dispatch(getGlobalAction(localAction))
            localState = getLocalState(self.state)
            return []
        }
        
        let cancellable = self.$state.sink { [weak localStore] updatedGlobalState in
            localStore?.state = getLocalState(updatedGlobalState)
        }
        
        localStore.viewCancellable = cancellable
        return localStore
    }
}

public func combine<State,Action>(_ reducers:Reducer<State,Action>... ) -> Reducer<State,Action> {
    return { state, action in
        reducers.flatMap { $0( &state, action) }
    }
}

public func pullback<LocalState,LocalAction,GlobalState,GlobalAction>(
    _ reducer:@escaping Reducer<LocalState,LocalAction>,
    localStateKeyPath: WritableKeyPath<GlobalState,LocalState>,
    localActionKeyPath: WritableKeyPath<GlobalAction,LocalAction?>) -> Reducer<GlobalState,GlobalAction> {
    return { globalState, globalAction in
        var localState = globalState[keyPath: localStateKeyPath]
        guard let localAction = globalAction[keyPath: localActionKeyPath] else { return [] }
        
        let localEffects = reducer( &localState, localAction)
        //Put local state into global state
        globalState[keyPath: localStateKeyPath] = localState
        //Put local action into global actions
        return localEffects.map { localEffect in
            localEffect.map { localAction -> GlobalAction in
                var globalAction = globalAction
                globalAction[keyPath: localActionKeyPath] = localAction
                return globalAction
            }
            .eraseToEffect()
        }
    }
}
