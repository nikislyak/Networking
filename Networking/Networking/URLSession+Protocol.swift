//
//  URLSession+Protocol.swift
//  Networking
//
//  Created by Nikita Kislyakov on 30.01.2020.
//  Copyright © 2020 Nikita Kislyakov. All rights reserved.
//

import Foundation
import Combine

extension URLSession: URLSessionProtocol {
    public func dataTaskPublisher(for request: URLRequest) -> AnyPublisher<DataTaskResult, Error> {
        (dataTaskPublisher(for: request) as URLSession.DataTaskPublisher)
            .mapError { $0 as Error }
            .eraseToAnyPublisher()
    }
}
