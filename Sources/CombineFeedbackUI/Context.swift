import SwiftUI
import Combine

@dynamicMemberLookup
public final class Context<State, Event>: ObservableObject {
    @Published
    private var state: State
    private var bag = Set<AnyCancellable>()
    private let send: (Event) -> Void
    private let mutate: (Mutation<State>) -> Void
    
    init(store: Store<State, Event>) {
        self.state = store.state
        self.send = store.send
        self.mutate = store.mutate
        store.$state.assign(to: \.state, weakly: self).store(in: &bag)
    }
        
    public init(
        state: State,
        send: @escaping (Event) -> Void,
        mutate: @escaping (Mutation<State>) -> Void
    ) {
        self.state = state
        self.send = send
        self.mutate = mutate
    }
    
    public subscript<U>(dynamicMember keyPath: KeyPath<State, U>) -> U {
        return state[keyPath: keyPath]
    }
    
    public func send(event: Event) {
        send(event)
    }
    
    public func view<LocalState: Equatable, LocalEvent>(
        value: WritableKeyPath<State, LocalState>,
        event: @escaping (LocalEvent) -> Event
    ) -> Context<LocalState, LocalEvent> {
        view(value: value, event: event, removeDuplicates: ==)
    }

    public func view<LocalState, LocalEvent>(
        value: WritableKeyPath<State, LocalState>,
        event: @escaping (LocalEvent) -> Event,
        removeDuplicates: @escaping (LocalState, LocalState) -> Bool
    ) -> Context<LocalState, LocalEvent> {
        let localContext = Context<LocalState, LocalEvent>(
            state: state[keyPath: value],
            send: { [weak self] localEvent in
                self?.send(event(localEvent))
            },
            mutate: { [weak self] (mutation: Mutation<LocalState>) in
                let superMutation: Mutation<State> = Mutation  { state in
                    mutation.mutate(&state[keyPath: value])
                }
                self?.mutate(superMutation)
            }
        )
        
        $state.map(value)
            .removeDuplicates(by: removeDuplicates)
            .assign(to: \.state, weakly: localContext)
            .store(in: &localContext.bag)
        
        return localContext
    }
    
    public func binding<U>(for keyPath: KeyPath<State, U>, event: @escaping (U) -> Event) -> Binding<U> {
        return Binding(
            get: {
                self.state[keyPath: keyPath]
            },
            set: {
                self.send(event: event($0))
            }
        )
    }
    
    public func binding<U>(for keyPath: KeyPath<State, U>, event: Event) -> Binding<U> {
        return Binding(
            get: {
                self.state[keyPath: keyPath]
            },
            set: { _ in
                self.send(event: event)
            }
        )
    }
    
    public func binding<U>(for keyPath: WritableKeyPath<State, U>) -> Binding<U> {
        return Binding(
            get: {
                self.state[keyPath: keyPath]
            },
            set: {
                self.mutate(Mutation(keyPath: keyPath, value: $0))
            }
        )
    }
    
    public func binding<U, T>(for keyPath: WritableKeyPath<State, U>, get: @escaping (U) -> T, set: @escaping (T) -> (U)) -> Binding<T> {
        return Binding(
            get: {
                get(self.state[keyPath: keyPath])
            },
            set: {
                self.mutate(Mutation(keyPath: keyPath, value: set($0)))
            }
        )
    }
    
    public func action(for event: Event, async: Bool = false) -> () -> Void {
        let action = { [weak self] () -> Void in
            self?.send(event: event)
        }

        return {
            if async {
                DispatchQueue.main.async(execute: action)
            } else {
                action()
            }
        }
    }

    public func action(for event: Event, asyncAfter delay: TimeInterval) -> () -> Void {
        let action = self.action(for: event, async: false)

        return {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    }

    /// Returns publisher which publishes **unique** updates of value of a given `keyPath`.
    /// - Note: `nil` values are also published.
    public func updates<U>(for keyPath: KeyPath<State, U>) -> AnyPublisher<U, Never> where U: Equatable {
        return $state
            .map(keyPath)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

public protocol OptionalProtocol {
    associatedtype Wrapped
    var wrapped: Wrapped? { get set }
}

extension Optional: OptionalProtocol {
    public var wrapped: Wrapped? {
        get {
            return self
        }
        set {
            self = newValue
        }
    }
}

extension Context where State: OptionalProtocol {
    public func binding<U>(for keyPath: WritableKeyPath<State.Wrapped, U>, defaultValue: U) -> Binding<U> {
        return Binding(
            get: {
                self.state.wrapped?[keyPath: keyPath] ?? defaultValue
            },
            set: {
                self.mutate(Mutation(keyPath: keyPath, value2: $0))
            }
        )
    }

    public subscript<U>(dynamicMember keyPath: KeyPath<State.Wrapped, U>, defaultValue: U) -> U {
        return state.wrapped?[keyPath: keyPath] ?? defaultValue
    }
}
