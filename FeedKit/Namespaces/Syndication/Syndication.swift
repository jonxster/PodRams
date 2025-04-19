//
// Syndication.swift
//
// Copyright (c) 2016 - 2025 Nuno Dias
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import XMLKit

/// Provides syndication hints to aggregators and others picking up this RDF Site
/// Summary (RSS) feed regarding how often it is updated. For example, if you
/// updated your file twice an hour, updatePeriod would be "hourly" and
/// updateFrequency would be "2". The syndication module borrows from Ian Davis's
/// Open Content Syndication (OCS) directory format. It supercedes the RSS 0.91
/// skipDay and skipHour elements.
///
/// See http://web.resource.org/rss/1.0/modules/syndication/
public struct Syndication {
  // MARK: Lifecycle

  public init(
    updatePeriod: SyndicationUpdatePeriod? = nil,
    updateFrequency: Int? = nil,
    updateBase: Date? = nil
  ) {
    self.updatePeriod = updatePeriod
    self.updateFrequency = updateFrequency
    self.updateBase = updateBase
  }

  // MARK: Public

  /// Describes the period over which the channel format is updated. Acceptable
  /// values are: hourly, daily, weekly, monthly, yearly. If omitted, daily is
  /// assumed.
  public var updatePeriod: SyndicationUpdatePeriod?

  /// Used to describe the frequency of updates in relation to the update period.
  /// A positive integer indicates how many times in that period the channel is
  /// updated. For example, an updatePeriod of daily, and an updateFrequency of
  /// 2 indicates the channel format is updated twice daily. If omitted a value
  /// of 1 is assumed.
  public var updateFrequency: Int?

  /// Defines a base date to be used in concert with updatePeriod and
  /// updateFrequency to calculate the publishing schedule. The date format takes
  /// the form: yyyy-mm-ddThh:mm
  public var updateBase: Date?
}

// MARK: - XMLNamespaceDecodable

extension Syndication: XMLNamespaceCodable {}

// MARK: - Sendable

extension Syndication: Sendable {}

// MARK: - Equatable

extension Syndication: Equatable {}

// MARK: - Hashable

extension Syndication: Hashable {}

// MARK: - Codable

extension Syndication: Codable {
  private enum CodingKeys: String, CodingKey {
    case updatePeriod = "sy:updatePeriod"
    case updateFrequency = "sy:updateFrequency"
    case updateBase = "sy:updateBase"
  }

  public init(from decoder: any Decoder) throws {
    let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

    updatePeriod = try container.decodeIfPresent(SyndicationUpdatePeriod.self, forKey: CodingKeys.updatePeriod)
    updateFrequency = try container.decodeIfPresent(Int.self, forKey: CodingKeys.updateFrequency)
    updateBase = try container.decodeIfPresent(Date.self, forKey: CodingKeys.updateBase)
  }

  public func encode(to encoder: any Encoder) throws {
    var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

    try container.encodeIfPresent(updatePeriod, forKey: CodingKeys.updatePeriod)
    try container.encodeIfPresent(updateFrequency, forKey: CodingKeys.updateFrequency)
    try container.encodeIfPresent(updateBase, forKey: CodingKeys.updateBase)
  }
}
