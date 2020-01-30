//
//  NetworkTests.swift
//  Eve-Ent-Tests
//
//  Created by Nikita Kislyakov on 28.01.2020.
//

import XCTest
import Combine
import Foundation
@testable import Networking

class MockURLSession: URLSessionProtocol {
    func dataTaskPublisher(for request: URLRequest) -> AnyPublisher<DataTaskResult, Error> {
        Just((data: try! JSONEncoder().encode(1), response: URLResponse()))
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}

class MockValidator: NetworkResponseValidator {
    var value: Bool = true
    
    func isValid(response: URLResponse) -> Bool {
        value
    }
}

class MockRestorer: RequestRestorer {
    func restore() -> AnyPublisher<Void, Error> {
        Result.Publisher(()).eraseToAnyPublisher()
    }
}

class NetworkTests: XCTestCase {
    let url = URL(string: "https://github.com/")!
    
    var mockValidator: MockValidator!
    var mockRestorer: MockRestorer!
    var mockSession: MockURLSession!
    var network: Network!

    override func setUp() {
        super.setUp()
        
        mockValidator = MockValidator()
        mockRestorer = MockRestorer()
        
        mockSession = MockURLSession()
        
        network = Network(
            env: Network.Environment(
                urlSession: mockSession,
                baseUrl: url,
                decoder: .init(),
                encoder: .init(),
                retriers: Network.Environment.Retriers(
                    responseValidator: mockValidator,
                    requestRestorer: mockRestorer
                )
            )
        )
    }

    override func tearDown() {
        mockValidator = nil
        mockSession = nil
        network = nil
        
        super.tearDown()
    }

    func testPerformWithoutValidation() {
        waiting { exp in
            network
                .perform(request: URLRequest(url: url))
                .sink(exp: exp) { (data: Int) in
                    XCTAssertEqual(data, 1)
                    
                    exp.fulfill()
                }
        }
    }
    
    func testPerformWithAlwaysTrueValidation() {
        mockValidator.value = true
        
        waiting { exp in
            network
                .perform(request: URLRequest(url: url))
                .sink(exp: exp) { (data: Int) in
                    XCTAssertEqual(data, 1)
                    
                    exp.fulfill()
            }
        }
    }
    
    func testPerformWithAlwaysFalseValidation() {
        mockValidator.value = false
        
        waiting { exp in
            network
                .perform(request: URLRequest(url: url))
                .sink(exp: exp) { (data: Int) in
                    XCTAssertEqual(data, 1)
                    
                    exp.fulfill()
                }
        }
    }
    
    func testRequestThenPerform() throws {
        waiting { exp in
            network
                .request(path: "")
                .body(data: Data())
                .perform()
                .sink(exp: exp) { (value: Int) in
                    XCTAssertEqual(value, 1)
                    
                    exp.fulfill()
                }
        }
    }
    
    func testRequestMethod() throws {
        let expectedRequest = URLRequest(url: url)
        let request = network.request(path: "") as IncompleteRequest<String>
        
        assertChangesEqual(
            mut(expectedRequest) { $0.httpMethod = "GET" },
            request.method(.GET)
        )
        
        assertChangesEqual(
            mut(expectedRequest) { $0.addValue("application/json", forHTTPHeaderField: "Content-Type") },
            request.header(key: "Content-Type", value: "application/json")
        )
        
        assertChangesEqual(
            mut(expectedRequest) { $0.allowsCellularAccess = true },
            request.set(\.allowsCellularAccess, true)
        )
        
        try assertChangesEqual(
            mut(expectedRequest) { $0.httpBody = try JSONEncoder().encode(1) },
            request.body(data: try JSONEncoder().encode(1))
        )
        
        let headers = [
            "a": "a",
            "b": "b"
        ]
        
        assertChangesEqual(
            mut(expectedRequest) { r in headers.forEach { r.addValue($0.value, forHTTPHeaderField: $0.key) } },
            request.headers(headers)
        )
        
        var comp = URLComponents(url: expectedRequest.url!, resolvingAgainstBaseURL: false)!
        
        comp.queryItems = (comp.queryItems ?? []) + [URLQueryItem(name: "a", value: "a")]
        comp.queryItems = (comp.queryItems ?? []) + [URLQueryItem(name: "b", value: "b")]
        
        assertChangesEqual(
            mut(expectedRequest) { $0.url = comp.url },
            request.params(["a": "a", "b": "b"])
        )
    }
    
    func testURLBodyEncoding() throws {
        let expected = URLRequest(url: url)
        
        let request = network
            .request(
                path: "",
                encoding: URLEncoding(destination: .httpBody)
            ) as IncompleteRequest<String>
        
        assertChangesEqual(
            mut(expected) {
                $0.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
                $0.httpBody = "a=a&b=b&c=8".data(using: .utf8)
            },
            request.params(["a": "a", "b": "b", "c": 8])
        )
        
        assertChangesEqual(
            mut(expected) {
                $0.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
                $0.httpBody = "a=a&b=b&c=8".data(using: .utf8)
            },
            request
                .param(key: "a", value: "a")
                .param(key: "b", value: "b")
                .param(key: "c", value: 8)
        )
    }
}

func mut<T>(_ instance: T, _ mutator: (inout T) throws -> Void) rethrows -> T {
    var copy = instance
    
    try mutator(&copy)
    
    return copy
}

func assertChangesEqual<R: Decodable>(
    _ orig: @autoclosure () throws -> URLRequest,
    _ test: @autoclosure () throws -> IncompleteRequest<R>
) rethrows {
    XCTAssertEqual(try orig(), try test().builder.build())
}
