import SwiftUI
import CoreData

/// The Classroom screen's early-pickup reminder rows: the switch and how
/// long before each pickup it comes. Rescheduling follows either.
struct EarlyPickupReminderRows: View {
    let context: NSManagedObjectContext?

    @AppStorage(EarlyPickupReminder.enabledKey) private var isOn = true
    @AppStorage(EarlyPickupReminder.leadKey) private var lead = EarlyPickupReminder.defaultLeadMinutes

    var body: some View {
        Toggle("Early pickup reminder", isOn: $isOn)
            .task(id: "\(isOn)|\(lead)") {
                guard let context else { return }
                // After setup's Not Now, opening Classroom doesn't ask iOS
                // about notifications; turning a reminder on does.
                await EarlyPickupReminder.reschedule(
                    in: context, asksPermission: !AssistantSetupReminder.declinedInSetup()
                )
            }
        if isOn {
            Picker("Remind me", selection: $lead) {
                ForEach(EarlyPickupReminder.leadChoices, id: \.self) { minutes in
                    Text("\(minutes) min before").tag(minutes)
                }
            }
        }
    }
}
