//
//  RequestBuilder.swift
//  Data
//
//  Created by Nikita Kislyakov on 28.01.2020.
//

import Foundation

extension URLRequest {
    public var method: HTTPMethod? {
        httpMethod.flatMap { HTTPMethod(rawValue: $0.uppercased()) }
    }
}

public struct RequestBuilder {
    private let request: URLRequest
    private let encoding: ParameterEncoding
    private let params: [String: Any]
    
    public init(baseUrl: URL, path: String, encoding: ParameterEncoding) {
        self.request = .init(url: baseUrl.appendingPathComponent(path))
        self.encoding = encoding
        self.params = [:]
    }
    
    private init(request: URLRequest, encoding: ParameterEncoding, params: [String: Any]) {
        self.request = request
        self.encoding = encoding
        self.params = params
    }
    
    private func withCopy<T>(of smth: T, _ configure: (inout T) -> Void) -> T {
        var copy = smth
        
        configure(&copy)
        
        return copy
    }
    
    public func method(_ httpMethod: HTTPMethod) -> Self {
        .init(
            request: withCopy(of: request) {
                $0.httpMethod = httpMethod.rawValue
            },
            encoding: encoding,
            params: params
        )
    }
    
    public func headers(_ dict: [String: String]) -> Self {
        .init(
            request: withCopy(of: request) { req in
                dict.forEach {
                    req.addValue($0.value, forHTTPHeaderField: $0.key)
                }
            },
            encoding: encoding,
            params: params
        )
    }
    
    public func header(key: String, value: String) -> Self {
        .init(
            request: withCopy(of: request) {
                $0.addValue(value, forHTTPHeaderField: key)
            },
            encoding: encoding,
            params: params
        )
    }
    
    public func set<V>(_ kp: WritableKeyPath<URLRequest, V>, _ value: V) -> Self {
        .init(
            request: withCopy(of: request) {
                $0[keyPath: kp] = value
            },
            encoding: encoding,
            params: params
        )
    }
    
    public func params(_ params: [String: Any]) -> Self {
        .init(
            request: request,
            encoding: encoding,
            params: .init(self.params.map { $0 } + params.map { $0 }) { first, _ in first }
        )
    }
    
    public func param<V>(key: String, value: V) -> Self {
        .init(
            request: request,
            encoding: encoding,
            params: .init(params.map { $0 } + [(key, value)]) { first, _ in first }
        )
    }
    
    public func body(data: Data) -> Self {
        .init(
            request: withCopy(of: request) {
                $0.httpBody = data
            },
            encoding: encoding,
            params: params
        )
    }
    
    public func build() -> URLRequest {
        withCopy(of: request) { copy in
            copy = encoding.encode(copy, with: params)
        }
    }
}
