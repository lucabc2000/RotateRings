//
//  LevelBrowserView.swift
//  RotateRings
//
//  Debug only. Lists every generated level with its solver metrics, opens a detail page with the
//  runner-ups, and exports the reviewer's swaps for the generator. Plays the shipped levels or
//  another level set (`LevelSets`).
//

#if DEBUG
import SwiftUI
import UIKit

struct LevelBrowserView: View {
    /// Plays a level file in the real scene, outside the campaign. The second argument is a title for
    /// the header.
    let onPlay: (LevelFile, String) -> Void
    /// Moves the campaign to this level number, so completing it continues with the next.
    let onPlayLevel: (Int) -> Void
    /// Plays the levels of another set from now on.
    let onSwitchSet: (Bundle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var report: LevelReport?
    @State private var candidates: CandidateStore?
    @State private var loadError: String?
    @State private var showExported = false
    @State private var setName = LevelSets.current
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
                            LevelDetailView(level: level, candidates: candidates, onPlay: onPlay, onPlayLevel: onPlayLevel)
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
            .navigationTitle(setName ?? "Level Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Level set", selection: $setName) {
                            Text("Shipped levels").tag(String?.none)
                            ForEach(LevelSets.names, id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        .pickerStyle(.menu)
                    } label: {
                        Label("Level set", systemImage: "square.stack.3d.up")
                    }
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
        .onChange(of: setName) {
            LevelSets.current = setName
            swaps.reload()
            onSwitchSet(.levels)
            load()
        }
    }

    private func load() {
        report = nil
        loadError = nil
        do {
            report = try LevelLoader.loadReport(in: .levels)
            candidates = try? LevelLoader.loadCandidates(in: .levels)
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
                Text("\(level.chosen.template) · \(level.chosen.pieceCount) pieces" + (swapped ? " · swapped" : "") + (level.pinned ? " · pinned" : "")
                     + (level.outOfBand == true ? " · out of band" : ""))
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
    LevelBrowserView(onPlay: { _, _ in }, onPlayLevel: { _ in }, onSwitchSet: { _ in })
}

enum DifficultyText {
    /// The quality difficulty with the tier when the report has them (the scale of the curve
    /// targets), otherwise the legacy score.
    static func score(_ candidate: LevelReport.Candidate) -> String {
        if let quality = candidate.quality {
            return String(format: "%.0f", quality.difficulty) + " · " + tier(quality)
        }
        return (candidate.metrics.isEstimate ? "≈" : "") + String(format: "%.0f", candidate.difficulty)
    }

    /// "t2", or "unplanned" when no bot plans the level.
    static func tier(_ quality: LevelQuality) -> String {
        quality.unplanned ? "unplanned" : "t\(quality.tier)"
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
