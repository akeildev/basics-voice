import SwiftUI

/// Boards "10 — Stats" (`1L4-0`), "· milestones & insights" (`G07-0`),
/// "· typing speed, reset & bar hover" (`GKB-0`) and "· empty" (`GPR-0`).
///
/// One editorial column on white — a hero total, today's line, the activity
/// ramp, then records, milestones and insights as hairline-separated lanes.
/// No cards: the numbers sit on the surface. Every figure comes from
/// `TranscriptionHistoryStore`; the typing speed comes from `SettingsStore`.
struct StatsView: View {
    @ObservedObject private var historyStore = TranscriptionHistoryStore.shared
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    @State private var showResetConfirmation: Bool = false
    @State private var showWPMEditor: Bool = false
    @State private var editingWPM: String = ""
    @State private var chartDays: Int = 30
    @State private var hoveredActivityIndex: Int?

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                self.heroSection
                self.todaySection
                self.activitySection
                self.recordsSection
                self.milestonesSection
                self.insightsSection
                self.resetSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.vertical, 34)
        }
        .background(self.theme.palette.cardBackground)
    }

    // MARK: - Hero

    private var heroSection: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Library · all time")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.accent)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(self.formatNumber(self.historyStore.totalWords))
                        .basicsLabel(56)
                        .foregroundStyle(self.theme.palette.primaryText)

                    Text("words dictated")
                        .basicsLabel(20)
                        .foregroundStyle(self.theme.palette.secondaryText)
                }

                Text(self.heroSentence)
                    .basicsProse(15)
                    .lineSpacing(6)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                self.typingSpeedButton
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            self.rangePicker
        }
    }

    private var heroSentence: String {
        guard !self.historyStore.entries.isEmpty else {
            return "No dictation saved yet. Your words, time saved and streaks build up here as soon as you start."
        }

        let days = self.activeDayCount
        let sessions = self.historyStore.entries.count
        let wpm = self.settings.userTypingWPM
        let saved = self.longFormTimeSaved(
            self.historyStore.timeSavedMinutes(typingWPM: wpm)
        )

        return "Across \(self.formatNumber(days)) active \(days == 1 ? "day" : "days") "
            + "and \(self.formatNumber(sessions)) \(sessions == 1 ? "session" : "sessions"). "
            + "At \(wpm) wpm typed, that is \(saved) you did not spend at a keyboard."
    }

    private var typingSpeedButton: some View {
        Button {
            self.editingWPM = "\(self.settings.userTypingWPM)"
            self.showWPMEditor = true
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(self.theme.palette.secondaryText)

                Text("Typing speed")
                    .basicsLabel(12)
                    .foregroundStyle(self.theme.palette.secondaryText)

                Text("\(self.settings.userTypingWPM) wpm")
                    .basicsMono(12)
                    .foregroundStyle(self.theme.palette.primaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(self.theme.palette.cardBackground)
                    .overlay(Capsule().stroke(self.theme.palette.cardBorder, lineWidth: 1))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Set the typing speed used to work out time saved")
        .popover(isPresented: self.$showWPMEditor) {
            self.wpmEditorPopover
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 4) {
            self.rangeSegment(days: 7, title: "7 days")
            self.rangeSegment(days: 30, title: "30 days")
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(self.theme.palette.sidebarBackground)
        )
    }

    private func rangeSegment(days: Int, title: String) -> some View {
        let isSelected = self.chartDays == days

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                self.chartDays = days
                self.hoveredActivityIndex = nil
            }
        } label: {
            Text(title)
                .basicsLabel(12)
                .foregroundStyle(isSelected ? self.theme.palette.primaryText : self.theme.palette.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .fill(isSelected ? self.theme.palette.cardBackground : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Typing speed popover

    private var wpmEditorPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your typing speed")
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text("Used to work out how much time dictation saved you.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                TextField("", text: self.$editingWPM)
                    .textFieldStyle(.plain)
                    .basicsMono(14)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(self.theme.palette.primaryText)
                    .frame(width: 74, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                            .fill(self.theme.palette.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                    .stroke(self.theme.palette.accent, lineWidth: 1)
                            )
                    )
                    .onSubmit { self.commitTypingSpeed() }

                Text("words per minute")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Average typing: 40 WPM")
                    .basicsProse(12)
                    .foregroundStyle(self.theme.palette.secondaryText)

                Text("Professional: 65-75 WPM")
                    .basicsProse(12)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                    .fill(self.theme.palette.sidebarBackground)
            )

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                self.popoverButton(title: "Cancel", isBrand: false) {
                    self.showWPMEditor = false
                }

                self.popoverButton(title: "Save", isBrand: true) {
                    self.commitTypingSpeed()
                }
            }
        }
        .padding(18)
        .frame(width: 288)
        .background(self.theme.palette.cardBackground)
    }

    private func popoverButton(title: String, isBrand: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .basicsButtonLabel(13)
                .foregroundStyle(isBrand ? .white : self.theme.palette.primaryText)
                .padding(.horizontal, isBrand ? 16 : 14)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .fill(isBrand ? self.theme.palette.accent : self.theme.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                .stroke(
                                    isBrand ? Color.clear : BasicsBorder.strong(self.theme, self.colorScheme),
                                    lineWidth: 1
                                )
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commitTypingSpeed() {
        if let wpm = Int(self.editingWPM.trimmingCharacters(in: .whitespaces)), wpm > 0 {
            self.settings.userTypingWPM = wpm
        }
        self.showWPMEditor = false
    }

    // MARK: - Today

    private var todaySection: some View {
        let summary = self.historyStore.todaySummary
        let streak = self.historyStore.currentStreak

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.secondaryText)

                Spacer()

                if streak > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "flame")
                            .font(.system(size: 10, weight: .medium))
                        Text("\(streak) \(streak == 1 ? "day" : "days")")
                            .basicsLabel(12)
                    }
                    .foregroundStyle(self.theme.palette.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(self.theme.palette.accent.opacity(0.10)))
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 36) {
                self.todayMetric(
                    value: self.formatNumber(summary.words),
                    label: "words"
                )
                self.todayMetric(
                    value: summary.formattedTimeSaved(typingWPM: self.settings.userTypingWPM),
                    label: "saved"
                )
                self.todayMetric(
                    value: "\(summary.transcriptions)",
                    label: "sessions"
                )

                Text(self.motivationalMessage(wordsToday: summary.words, streak: streak))
                    .basicsProse(14)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 20)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)
        }
    }

    private func todayMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(value)
                .basicsLabel(28)
                .foregroundStyle(self.theme.palette.primaryText)
                .lineLimit(1)

            Text(label)
                .basicsLabel(13)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
    }

    /// Motivational message that scales with today's activity level.
    private func motivationalMessage(wordsToday: Int, streak: Int) -> String {
        if wordsToday == 0 {
            return streak > 0
                ? "Keep the streak alive — say a few words."
                : "Ready when you are. Start dictating to save time."
        }
        if wordsToday < 100 { return "Warming up. Every word counts." }
        if wordsToday < 500 { return "Solid pace — you're saving real time today." }
        if wordsToday < 1500 {
            return streak > 2 ? "On fire. The streak is paying off." : "Strong day. Your hands thank you."
        }
        return "Outstanding. You've reclaimed serious time today."
    }

    // MARK: - Activity

    private var activitySection: some View {
        let data = self.historyStore.dailyWordCounts(days: self.chartDays)
        let maxWords = data.map { $0.words }.max() ?? 0

        return VStack(alignment: .leading, spacing: 14) {
            Text("Activity")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            if maxWords == 0 {
                self.activityEmptyState
            } else {
                self.activityChart(data: data, maxWords: maxWords)
                self.activityAxis(data: data)
            }
        }
    }

    private var activityEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(self.theme.palette.tertiaryText)

            Text("No activity yet")
                .basicsLabel(15)
                .foregroundStyle(self.theme.palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                .fill(self.theme.palette.sidebarBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                        .strokeBorder(
                            BasicsBorder.strong(self.theme, self.colorScheme),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                        )
                )
        )
    }

    private func activityChart(data: [(date: Date, words: Int)], maxWords: Int) -> some View {
        HStack(alignment: .bottom, spacing: self.chartDays == 7 ? 12 : 7) {
            ForEach(Array(data.enumerated()), id: \.offset) { index, item in
                self.activityBar(index: index, item: item, maxWords: maxWords)
            }
        }
        .frame(height: 150)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
        .zIndex(1)
    }

    private func activityBar(
        index: Int,
        item: (date: Date, words: Int),
        maxWords: Int
    ) -> some View {
        let isHovered = self.hoveredActivityIndex == index
        let height = item.words > 0 && maxWords > 0
            ? max(8, CGFloat(item.words) / CGFloat(maxWords) * 150)
            : 4

        return ZStack(alignment: .bottom) {
            Color.clear

            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(self.barColor(words: item.words, maxWords: maxWords))
                .frame(height: height)
                .opacity(isHovered ? 0.82 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if isHovered {
                self.activityTooltip(for: item)
                    .fixedSize()
                    .offset(y: -14)
            }
        }
        .zIndex(isHovered ? 1 : 0)
        .onHover { hovering in
            self.hoveredActivityIndex = hovering ? index : nil
        }
    }

    /// The evergreen ramp, bucketed by each day's share of the busiest day in
    /// the window. Zero days keep the muted well so the row still reads as a
    /// calendar rather than a gap.
    private func barColor(words: Int, maxWords: Int) -> Color {
        guard words > 0, maxWords > 0 else { return self.theme.palette.sidebarBackground }

        let share = Double(words) / Double(maxWords)
        switch share {
        case ..<0.2: return BasicsTokens.Green.g100
        case ..<0.4: return BasicsTokens.Green.g200
        case ..<0.65: return BasicsTokens.Green.g300
        case ..<0.95: return BasicsTokens.Green.g400
        default: return self.theme.palette.accent
        }
    }

    private func activityTooltip(for item: (date: Date, words: Int)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(Self.tooltipDateFormatter.string(from: item.date))
                .basicsLabel(12)
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("\(self.formatNumber(item.words)) \(item.words == 1 ? "word" : "words")")
                .basicsMono(11)
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: BasicsTokens.Radius.md, style: .continuous)
                .fill(BasicsTokens.Ink.foreground)
                .shadow(color: BasicsTokens.Ink.foreground.opacity(0.18), radius: 12, y: 10)
        )
        .allowsHitTesting(false)
    }

    private func activityAxis(data: [(date: Date, words: Int)]) -> some View {
        HStack {
            Text(data.first.map { Self.axisDateFormatter.string(from: $0.date) } ?? "")
                .basicsMono(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            Spacer()

            Text(data.last.map { Self.axisDateFormatter.string(from: $0.date) } ?? "")
                .basicsMono(11)
                .foregroundStyle(self.theme.palette.tertiaryText)
        }
    }

    // MARK: - Personal records

    private var recordsSection: some View {
        let records: [(label: String, value: Int, unit: String, isBrand: Bool)] = [
            ("Current streak", self.historyStore.currentStreak, "days", true),
            ("Best streak", self.historyStore.bestStreak, "days", false),
            ("Busiest day", self.historyStore.mostWordsInDay, "words", false),
            ("Most in a day", self.historyStore.mostTranscriptionsInDay, "sessions", false),
            ("Longest transcription", self.historyStore.longestTranscriptionWords, "words", false),
        ]

        return VStack(alignment: .leading, spacing: 14) {
            Text("Personal records")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            HStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.offset) { index, record in
                    self.recordCell(record)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .overlay(alignment: .leading) {
                            if index > 0 {
                                Rectangle()
                                    .fill(self.theme.palette.separator)
                                    .frame(width: 1)
                            }
                        }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                    .fill(self.theme.palette.windowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous)
                    .stroke(self.theme.palette.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BasicsTokens.Radius.lg, style: .continuous))
        }
    }

    private func recordCell(_ record: (label: String, value: Int, unit: String, isBrand: Bool)) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(record.label)
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(self.formatNumber(record.value))
                    .basicsLabel(28)
                    .foregroundStyle(record.isBrand ? self.theme.palette.accent : self.theme.palette.primaryText)
                    .lineLimit(1)

                Text(record.unit)
                    .basicsLabel(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    // MARK: - Milestones

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Milestones")
                    .basicsMicroLabel(11)
                    .foregroundStyle(self.theme.palette.tertiaryText)

                Spacer()

                Text("\(self.historyStore.totalMilestonesAchieved)/\(self.historyStore.totalMilestonesPossible)")
                    .basicsMono(12)
                    .foregroundStyle(self.theme.palette.accent)
            }

            self.milestoneRow(title: "Words", milestones: self.historyStore.wordMilestones)
            self.milestoneRow(title: "Transcriptions", milestones: self.historyStore.transcriptionMilestones)
            self.milestoneRow(title: "Streak", milestones: self.historyStore.streakMilestones)
        }
    }

    private func milestoneRow(
        title: String,
        milestones: [(target: Int, achieved: Bool, label: String)]
    ) -> some View {
        HStack(spacing: 14) {
            Text(title)
                .basicsLabel(13)
                .foregroundStyle(self.theme.palette.secondaryText)
                .frame(width: 104, alignment: .leading)

            ForEach(Array(milestones.enumerated()), id: \.offset) { _, milestone in
                self.milestoneChip(milestone)
            }

            Spacer(minLength: 0)
        }
    }

    private func milestoneChip(_ milestone: (target: Int, achieved: Bool, label: String)) -> some View {
        HStack(spacing: 5) {
            Image(systemName: milestone.achieved ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    milestone.achieved
                        ? self.theme.palette.accent
                        : BasicsBorder.strong(self.theme, self.colorScheme)
                )

            Text(milestone.label)
                .basicsLabel(12)
                .foregroundStyle(
                    milestone.achieved ? self.theme.palette.accent : self.theme.palette.tertiaryText
                )
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            Capsule().fill(
                milestone.achieved
                    ? self.theme.palette.accent.opacity(0.10)
                    : self.theme.palette.sidebarBackground
            )
        )
    }

    // MARK: - Insights

    private var insightsSection: some View {
        let topApps = self.historyStore.topAppsFormatted(limit: 3).joined(separator: ", ")
        let insights: [(label: String, value: String)] = [
            ("Top apps", topApps.isEmpty ? "No data yet" : topApps),
            ("AI enhanced", "\(self.historyStore.aiEnhancementRate)%"),
            ("Peak time", self.historyStore.peakHourFormatted),
            ("Avg length", "\(self.historyStore.averageWordsPerTranscription) words"),
        ]

        return VStack(alignment: .leading, spacing: 16) {
            Text("Insights")
                .basicsMicroLabel(11)
                .foregroundStyle(self.theme.palette.tertiaryText)

            HStack(spacing: 0) {
                ForEach(Array(insights.enumerated()), id: \.offset) { index, insight in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(insight.label)
                            .basicsMicroLabel(11)
                            .foregroundStyle(self.theme.palette.tertiaryText)

                        Text(insight.value)
                            .basicsLabel(18)
                            .foregroundStyle(self.theme.palette.primaryText)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.vertical, 18)
                    .padding(.leading, index == 0 ? 0 : 20)
                    .padding(.trailing, index == insights.count - 1 ? 0 : 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(alignment: .leading) {
                        if index > 0 {
                            Rectangle()
                                .fill(self.theme.palette.separator)
                                .frame(width: 1)
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(self.theme.palette.separator)
                    .frame(height: 1)
            }
        }
    }

    // MARK: - Reset

    private var resetSection: some View {
        let isEmpty = self.historyStore.entries.isEmpty

        return HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Reset all stats")
                    .basicsLabel(15)
                    .foregroundStyle(self.theme.palette.primaryText)

                Text(isEmpty
                    ? "Nothing to reset — there are no transcriptions yet."
                    : "Deletes every transcription and returns all counts, streaks and records to zero.")
                    .basicsProse(13)
                    .foregroundStyle(self.theme.palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                self.showResetConfirmation = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .medium))
                    Text("Reset all stats")
                        .basicsButtonLabel(13)
                }
                .foregroundStyle(
                    isEmpty ? self.theme.palette.tertiaryText : BasicsTokens.Semantic.danger
                )
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                        .fill(isEmpty ? self.theme.palette.sidebarBackground : self.theme.palette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: BasicsTokens.Radius.sm, style: .continuous)
                                .stroke(
                                    isEmpty
                                        ? self.theme.palette.cardBorder
                                        : BasicsBorder.strong(self.theme, self.colorScheme),
                                    lineWidth: 1
                                )
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isEmpty)
        }
        .padding(.top, 26)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(self.theme.palette.separator)
                .frame(height: 1)
        }
        .alert("Reset all stats", isPresented: self.$showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset everything", role: .destructive) {
                self.historyStore.clearAllHistory()
            }
        } message: {
            Text(
                "This will permanently delete all \(self.historyStore.entries.count) transcriptions and reset all statistics. This action cannot be undone."
            )
        }
    }

    // MARK: - Helpers

    /// Unique days with at least one saved transcription.
    private var activeDayCount: Int {
        let calendar = Calendar.current
        var days = Set<Date>()
        for entry in self.historyStore.entries {
            days.insert(calendar.startOfDay(for: entry.timestamp))
        }
        return days.count
    }

    /// "32 hours 13 minutes" — the hero sentence reads as prose, so the compact
    /// "32h 13m" the metric row uses would be wrong here.
    private func longFormTimeSaved(_ minutes: Double) -> String {
        guard minutes >= 1 else { return "less than a minute" }

        let total = Int(minutes)
        let hours = total / 60
        let mins = total % 60

        if hours == 0 {
            return "\(mins) \(mins == 1 ? "minute" : "minutes")"
        }
        let hourText = "\(hours) \(hours == 1 ? "hour" : "hours")"
        if mins == 0 { return hourText }
        return "\(hourText) \(mins) \(mins == 1 ? "minute" : "minutes")"
    }

    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

#Preview {
    StatsView()
        .frame(width: 1096, height: 900)
        .environment(\.theme, AppTheme.light(accent: BasicsTokens.Semantic.brand))
}
