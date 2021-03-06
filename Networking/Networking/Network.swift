//
//  Network.swift
//  Library
//
//  Created by Nikita Kislyakov on 23.01.2020.
//

import Foundation
import Combine

extension URLRequest {
    public func perform<R: Decodable>(on network: Network) -> AnyPublisher<R, Error> {
        network.perform(request: self)
    }
}

open class Network {
    let env: Environment
    
    public init(env: Environment) {
        self.env = env
    }
    
    public func request<R: Decodable>(
        path: String,
        encoding: ParameterEncoding = URLEncoding()
    ) -> IncompleteRequest<R> {
        .init(
            network: self,
            builder: modify(
                request: .init(
                    baseUrl: env.baseUrl,
                    path: path,
                    encoding: encoding
                )
            )
        )
    }
    
    open func modify(request: RequestBuilder) -> RequestBuilder {
        request
    }
    
    open func perform<R: Decodable>(request: URLRequest) -> AnyPublisher<R, Error> {
        env.urlSession
            .dataTaskPublisher(for: request)
            .mapError(NetworkError.other)
            .flatMap { [env] dataTaskResult -> AnyPublisher<DataTaskResult, NetworkError> in
                guard env.retriers?.responseValidator.isValid(response: dataTaskResult.response) ?? true else {
                    return Fail(error: .validation).eraseToAnyPublisher()
                }
                
                return Result.Publisher(dataTaskResult).eraseToAnyPublisher()
            }
            .catch { [env] error -> AnyPublisher<DataTaskResult, Error> in
                if error.validation {
                    guard let restorer = env.retriers?.requestRestorer else {
                        return Empty().eraseToAnyPublisher()
                    }
                    
                    return restorer
                        .restore()
                        .flatMap(maxPublishers: .max(1)) {
                            env.urlSession.dataTaskPublisher(for: request)
                        }
                        .eraseToAnyPublisher()
                } else {
                    return Fail(error: error).eraseToAnyPublisher()
                }
            }
            .map(\.data)
            .decode(type: R.self, decoder: env.responseDecoder)
            .eraseToAnyPublisher()
    }
}

public enum NetworkError: Error {
    case validation
    case other(Error)
    
    var validation: Bool {
        guard case .validation = self else {
            return false
        }
        
        return true
    }
    
    var other: Error? {
        guard case let .other(error) = self else {
            return nil
        }
        
        return error
    }
}

public protocol NetworkResponseValidator {
    func isValid(response: URLResponse) -> Bool
}

public protocol RequestRestorer {
    func restore() -> AnyPublisher<Void, Error>
}

public typealias DataTaskResult = (data: Data, response: URLResponse)

public protocol URLSessionProtocol {
    func dataTaskPublisher(for request: URLRequest) -> AnyPublisher<DataTaskResult, Error>
}

extension Network {
    public struct Environment {
        public let urlSession: URLSessionProtocol
        public let baseUrl: URL
        public let responseDecoder: JSONDecoder
        public let bodyEncoder: JSONEncoder
        public let retriers: Retriers?
        
        public init(
            urlSession: URLSessionProtocol,
            baseUrl: URL,
            responseDecoder: JSONDecoder,
            bodyEncoder: JSONEncoder,
            retriers: Network.Environment.Retriers?
        ) {
            self.urlSession = urlSession
            self.baseUrl = baseUrl
            self.responseDecoder = responseDecoder
            self.bodyEncoder = bodyEncoder
            self.retriers = retriers
        }
    }
}

extension Network.Environment {
    public struct Retriers {
        public let responseValidator: NetworkResponseValidator
        public let requestRestorer: RequestRestorer
        
        public init(
            responseValidator: NetworkResponseValidator,
            requestRestorer: RequestRestorer
        ) {
            self.responseValidator = responseValidator
            self.requestRestorer = requestRestorer
        }
    }
}
