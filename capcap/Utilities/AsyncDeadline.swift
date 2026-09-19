import Foundation

/// A deadline for system APIs which may never finish, even after cancellation.
/// A task group cannot provide this guarantee: leaving its scope waits for all
/// children. Late results here are discarded, and the caller resumes once only.
enum AsyncDeadline {
    struct TimedOut: Error {}

    static func run<Value>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> Value
    ) async throws -> Value {
        let state = State<Value>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.install(continuation)
                let worker = Task.detached {
                    do { state.finish(.success(try await operation())) }
                    catch { state.finish(.failure(error)) }
                }
                let timer = Task.detached {
                    do { try await Task.sleep(for: .seconds(seconds)) }
                    catch { return }
                    state.finish(.failure(TimedOut()))
                }
                state.install(tasks: [worker, timer])
            }
        } onCancel: {
            state.finish(.failure(CancellationError()))
        }
    }

    private final class State<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var result: Result<Value, Error>?
        private var continuation: CheckedContinuation<Value, Error>?
        private var tasks: [Task<Void, Never>] = []

        func install(_ continuation: CheckedContinuation<Value, Error>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }

        func install(tasks: [Task<Void, Never>]) {
            lock.lock()
            if result != nil {
                lock.unlock()
                tasks.forEach { $0.cancel() }
            } else {
                self.tasks = tasks
                lock.unlock()
            }
        }

        func finish(_ result: Result<Value, Error>) {
            lock.lock()
            guard self.result == nil else { lock.unlock(); return }
            self.result = result
            let continuation = self.continuation
            self.continuation = nil
            let tasks = self.tasks
            self.tasks = []
            lock.unlock()
            tasks.forEach { $0.cancel() }
            continuation?.resume(with: result)
        }
    }
}
