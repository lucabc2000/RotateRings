//
//  PriorityQueue.swift
//  RotateRings
//
//  A minimal binary min-heap used by the bounded solver search.
//

import Foundation

struct PriorityQueue<Element> {
    private var heap: [Element] = []
    private let isAhead: (Element, Element) -> Bool

    /// `isAhead(a, b)` is true when `a` should be popped before `b`.
    init(isAhead: @escaping (Element, Element) -> Bool) {
        self.isAhead = isAhead
    }

    var isEmpty: Bool { heap.isEmpty }
    var count: Int { heap.count }

    mutating func push(_ element: Element) {
        heap.append(element)
        var child = heap.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard isAhead(heap[child], heap[parent]) else { break }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Element? {
        guard !heap.isEmpty else { return nil }
        heap.swapAt(0, heap.count - 1)
        let top = heap.removeLast()
        var parent = 0
        while true {
            let left = 2 * parent + 1
            let right = left + 1
            var best = parent
            if left < heap.count, isAhead(heap[left], heap[best]) { best = left }
            if right < heap.count, isAhead(heap[right], heap[best]) { best = right }
            guard best != parent else { break }
            heap.swapAt(parent, best)
            parent = best
        }
        return top
    }
}
