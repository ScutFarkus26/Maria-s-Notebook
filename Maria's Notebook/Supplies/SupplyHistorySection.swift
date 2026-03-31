import SwiftUI

// MARK: - History Section

struct SupplyHistorySection: View {
    let transactions: [SupplyTransaction]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("History")
                .font(.headline)

            if transactions.isEmpty {
                Text("No transactions recorded yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .cardStyle()
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions) { transaction in
                        transactionRow(transaction)

                        if transaction.id != transactions.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
                .cardStyle(padding: 0)
            }
        }
    }

    private func transactionRow(_ transaction: SupplyTransaction) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(transaction.quantityChange >= 0 ? Color.green.opacity(UIConstants.OpacityConstants.accent) : Color.red.opacity(UIConstants.OpacityConstants.accent))
                    .frame(width: 32, height: 32)

                Image(systemName: transaction.quantityChange >= 0 ? "plus" : "minus")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(transaction.quantityChange >= 0 ? .green : .red)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(transaction.reason)
                    .font(.subheadline)

                Text(transaction.date ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(transaction.quantityChange >= 0 ? "+\(transaction.quantityChange)" : "\(transaction.quantityChange)")
                .font(.headline)
                .foregroundStyle(transaction.quantityChange >= 0 ? .green : .red)
        }
        .padding()
    }
}
