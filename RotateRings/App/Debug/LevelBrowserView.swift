//
//  LevelBrowserView.swift
//  RotateRings
//
//  Debug only. Lists every generated level with its solver metrics, opens a detail page with the
//  runner-ups, and exports the reviewer's swaps for the generator.
//

#if DEBUG
import SwiftUI
import UIKit

struct LevelBrowserView: View {
    /// Plays a level file in the real scene. The second argument is a title for the header.
    let onPlay: (LevelFile, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var report: LevelReport?
    @State private var candidates: CandidateStore?
    @State private var loadError: String?
    @State private var showExported = false
    private var swaps = LevelSwaps.shared

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    List {
                        ForEach(report.levels, id: \.number) { level in
                            NavigationLink(value: level.number) {
                                LevelRow(level: level, swapped: swaps.candidateID(for: level.number) != nil)
                            }
                            .listRowBackground(Color(uiColor: Palette.card))
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .navigationDestination(for: Int.self) { number in
                        if let level = report.levels.first(where: { $0.number == number }) {
                            LevelDetailView(level: level, candidates: candidates, onPlay: onPlay)
                        }
                    }
                } else if let loadError {
                    Text(loadError)
                        .foregroundStyle(Color(uiColor: Palette.textSecondary))
                        .padding()
                } else {
                    ProgressView()
                }
            }
            .background(Color(uiColor: Palette.backgroundBottom).ignoresSafeArea())
            .navigationTitle("Level Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Copy level-selection.json") { export() }
                        Button("Reset all swaps", role: .destructive) { swaps.resetAll() }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(report == nil)
                }
            }
            .alert("Selection copied", isPresented: $showExported) {
                Button("OK") {}
            } message: {
                Text("Paste the clipboard into RotateRings/Levels/level-selection.json and run LevelForge generate to make the swaps permanent.")
            }
        }
        .preferredColorScheme(.dark)
        .task { load() }
    }

    private func load() {
        do {
            report = try LevelLoader.loadReport(in: .main)
            candidates = try? LevelLoader.loadCandidates(in: .main)
        } catch {
            loadError = "No generation report in the bundle. Run LevelForge generate first.\n\(error.localizedDescription)"
        }
    }

    private func export() {
        guard let report else { return }
        UIPasteboard.general.string = swaps.exportSelection(report: report)
        showExported = true
    }
}

/// One line of the browser list.
private struct LevelRow: View {
    let level: LevelReport.Level
    let swapped: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("\(level.number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color(uiColor: Palette.backgroundBottom))
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(uiColor: Palette.pieceColor(named: swapped ? "yellow" : "mint"))))
            VStack(alignment: .leading, spacing: 2) {
                Text(level.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color(uiColor: Palette.textPrimary))
                Text("\(level.chosen.template) · \(level.chosen.pieceCount) pieces" + (swapped ? " · swapped" : "") + (level.pinned ? " · pinned" : ""))
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: Palette.textSecondary))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(DifficultyText.score(level.chosen))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Color(uiColor: Palette.textPrimary))
                Text(DifficultyText.summary(level.chosen.metrics))
                    .font(.caption)
                    .foregroundStyle(Color(uiColor: Palette.textSecondary))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview("Browser") {
    LevelBrowserView { _, _ in }
}

enum DifficultyText {
    static func score(_ candidate: LevelReport.Candidate) -> String {
        (candidate.metrics.isEstimate ? "≈" : "") + String(format: "%.0f", candidate.difficulty)
    }

    static func summary(_ metrics: SolverMetrics) -> String {
        let moves = "\(metrics.minMoves) move\(metrics.minMoves == 1 ? "" : "s")"
        guard metrics.deadEndMoves > 0 || metrics.isEstimate else { return moves }
        let rate = String(format: "%.0f%% traps", metrics.deadEndRate * 100)
        return "\(moves) · \(rate)"
    }

    static func move(_ move: SolverMove) -> String {
        // Sliding pieces are numbered "s…" (bars) and "l…" (L-bars) by the generator.
        let isSlide = move.piece.hasPrefix("s") || move.piece.hasPrefix("l")
        let verb = isSlide ? "Slide" : "Turn"
        let direction = isSlide ? (move.steps > 0 ? "forward" : "back") : (move.steps > 0 ? "counterclockwise" : "clockwise")
        let amount = isSlide ? "\(Int(abs(move.delta).rounded())) pt" : "\(abs(move.steps) * 45)°"
        let removed = move.removed.isEmpty ? "" : "  → frees \(move.removed.joined(separator: ", "))"
        return "\(verb) \(move.piece) \(direction) \(amount)\(removed)"
    }
}
#endif
