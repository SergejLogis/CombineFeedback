import XCTest
import Combine
import CombineFeedback
@testable import CombineFeedbackUI

private struct Test {

    struct State {
        var name: String?
        var age: Int?
    }

    enum Event {
        case onNameUpdate(String?)
        case onAgeUpdate(Int?)
    }

    final class ViewModel: CombineFeedbackUI.Store<State, Event> {
        init(initial: State) {
            super.init(
                initial: initial,
                feedbacks: [],
                reducer: Test.reducer()
            )
        }
    }

    static func reducer() -> Reducer<State, Event> {
        .init { state, event in
            switch event {
            case .onNameUpdate(let name):
                print("Updating name to: \(name ?? "nil")")
                state.name = name
            case .onAgeUpdate(let age):
                print("Updating age to: \(age.map { "\($0)" } ?? "nil")")
                state.age = age
            }
        }
    }

}

class CombineFeedbackUITests: XCTestCase {

    var nameSubscription: Cancellable?
    var ageSubscription: Cancellable?

    func test_state_property_update_publisher() {
        let context = Context(store: Test.ViewModel(
            initial: .init(name: nil, age: nil)
        ))

        var nameUpdatesCount = 0
        nameSubscription = context.updates(for: \.name).print().sink { _ in
            nameUpdatesCount += 1
        }

        var ageUpdatesCount = 0
        ageSubscription = context.updates(for: \.age).print().sink { _ in
            ageUpdatesCount += 1
        }

        asyncSerial(context.send(event: .onNameUpdate("John Doe")))
        asyncSerial(context.send(event: .onAgeUpdate(30)))
        asyncSerial(context.send(event: .onNameUpdate("John Doe")))
        asyncSerial(context.send(event: .onAgeUpdate(30)))
        asyncSerial(context.send(event: .onNameUpdate("Doe John")))
        asyncSerial(context.send(event: .onAgeUpdate(31)))
        asyncSerial(context.send(event: .onNameUpdate("Doe John")))
        asyncSerial(context.send(event: .onAgeUpdate(31)))
        asyncSerial(context.send(event: .onNameUpdate(nil)))
        asyncSerial(context.send(event: .onAgeUpdate(nil)))

        let delay: TimeInterval = 1
        let expectation = self.expectation(description: "Delay for \(Int(delay)) seconds")
        let result = XCTWaiter.wait(for: [expectation], timeout: delay)
        if result == XCTWaiter.Result.timedOut {
            XCTAssertEqual(4, nameUpdatesCount)
            XCTAssertEqual(4, ageUpdatesCount)
            nameSubscription?.cancel()
            ageSubscription?.cancel()
        }
    }

    private func asyncSerial(_ closure: @autoclosure @escaping () -> Void) {
        DispatchQueue.main.async(execute: closure)
    }

}
