//
//  LevelDetailView.swift
//  RotateRings
//
//  Debug only. One level: thumbnail, metrics, solution, and the runner-ups the reviewer can swap in.
//

#if DEBUG
import SwiftUI

struct LevelDetailView: View {
    let level: LevelReport.Level
    let candidates: CandidateStore?
    let onPlay: (LevelFile, String) -> Void

    @State private var chosenFile: LevelFile?
    private var swaps = LevelSwaps.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CandidateCard(
                    title: "Level \(level.number) · \(level.name)",
                    subtitle: level.pinned ? "pinned" : "generated pick",
                    candidate: level.chosen,
                    file: chosenFile,
                    isInUse: swaps.candidateID(for: level.number) == nil,
                    onPlay: onPlay,
                    onUse: { swaps.set(nil, for: level.number) }
                )

                if let target = level.targetDifficulty {
                    Text(String(format: "Curve target %.0f", target))
                        .font(.footnote)
                        .foregroundStyle(Color(uiColor: Palette.textSecondary))
                }

                if !level.runnerUps.isEmpty {
                    Text("Runner-ups")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color(uiColor: Palette.textPrimary))
                    ForEach(level.runnerUps, id: \.id) { runnerUp in
                        CandidateCard(
                            title: runnerUp.template,
                            subtitle: "seed \(runnerUp.seed)",
                            candidate: runnerUp,
                            file: candidates?.candidates[runnerUp.id],
                            isInUse: swaps.candidateID(for: level.number) == runnerUp.id,
                            onPlay: onPlay,
                            onUse: { swaps.set(runnerUp.id, for: level.number) }
                        )
                    }
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: Palette.backgroundBottom).ignoresSafeArea())
        .navigationTitle("Level \(level.number)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chosenFile = try? LevelLoader.load(level: level.number, in: .main)
        }
    }
}

#Preview("Detail") {
    let report = try? LevelLoader.loadReport(in: .main)
    let candidates = try? LevelLoader.loadCandidates(in: .main)
    return NavigationStack {
        if let level = report?.levels.first(where: { $0.number == 8 }) ?? report?.levels.first {
            LevelDetailView(level: level, candidates: candidates) { _, _ in }
        } else {
            Text("No report in bundle")
        }
    }
    .preferredColorScheme(.dark)
}

/// Thumbnail, metrics, solution and actions for one candidate.
private struct CandidateCard: View {
    let title: String
    let subtitle: String
    let candidate: LevelReport.Candidate
    let file: LevelFile?
    let isInUse: Bool
    let onPlay: (LevelFile, String) -> Void
    let onUse: () -> Void

    @State private var showSolution = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if let file {
                        LevelThumbnail(file: file)
                    } else {
                        Color(uiColor: Palette.cardBorder)
                    }
                }
                .frame(width: 108, height: 192)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: Palette.backgroundTop)))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: Palette.textPrimary))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Color(uiColor: Palette.textSecondary))
                    metric("Difficulty", DifficultyText.score(candidate))
                    metric("Min moves", "\(candidate.metrics.minMoves)")
                    metric("Dead-end moves", "\(candidate.metrics.deadEndMoves) / \(candidate.metrics.totalMoves)")
                    metric("Branching", String(format: "%.1f", candidate.metrics.branching))
                    if let freedom = candidate.metrics.freedom {
                        metric("Free pieces", String(format: "%.0f%%", freedom * 100))
                    }
                    metric("Pieces", "\(candidate.pieceCount) · \(candidate.kinds.joined(separator: ", "))")
                    if candidate.metrics.isEstimate {
                        Text("estimated (search capped)")
                            .font(.caption2)
                            .foregroundStyle(Color(uiColor: Palette.pieceColor(named: "yellow")))
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    if let file { onPlay(file, title) }
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(uiColor: Palette.pieceColor(named: "mint")))
                .disabled(file == nil)

                Button(isInUse ? "In use" : "Use this", action: onUse)
                    .buttonStyle(.bordered)
                    .disabled(isInUse)

                Button(showSolution ? "Hide solution" : "Solution") { showSolution.toggle() }
                    .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))

            if showSolution {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(candidate.solution.enumerated()), id: \.offset) { index, move in
                        Text("\(index + 1). \(DifficultyText.move(move))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color(uiColor: Palette.textSecondary))
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: Palette.card))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(isInUse ? Color(uiColor: Palette.pieceColor(named: "mint")) : Color(uiColor: Palette.cardBorder), lineWidth: 1.5))
        )
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Color(uiColor: Palette.textSecondary))
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(Color(uiColor: Palette.textPrimary))
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }
}
#endif
