import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            StepHeader(current: model.step)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            switch model.step {
            case .drop:
                DropStepView()
            case .configure:
                ConfigureStepView()
            case .retrieve:
                RetrieveStepView()
            case .importing:
                ImportStepView()
            case .done:
                DoneStepView()
            }
        }
        .background(.background)
    }
}

/// The 1-2-3-4-5 breadcrumb across the top of the window.
private struct StepHeader: View {
    let current: AppModel.Step

    var body: some View {
        HStack(spacing: 18) {
            ForEach(AppModel.Step.allCases, id: \.rawValue) { step in
                HStack(spacing: 7) {
                    stepBadge(step)
                    Text(step.title)
                        .font(.callout.weight(step == current ? .semibold : .regular))
                        .foregroundStyle(step == current ? .primary : .secondary)
                }
                if step != AppModel.Step.allCases.last {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(AppModel.Step.allCases.count): \(current.title)")
    }

    @ViewBuilder
    private func stepBadge(_ step: AppModel.Step) -> some View {
        let done = step.rawValue < current.rawValue
        ZStack {
            Circle()
                .fill(step == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .frame(width: 22, height: 22)
            if done {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(step.rawValue + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(step == current ? Color.white : .secondary)
            }
        }
    }
}
