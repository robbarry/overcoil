import SwiftUI

// UIKit's native wheel, with repeated values and transparent re-centering, avoids
// hard stops at 00/59 while retaining native gestures and VoiceOver adjustments.
struct CyclicTimePicker: UIViewRepresentable {
    var time: WatchTime
    var twelveHour: Bool
    var rowHeight: CGFloat
    var onSelection: (Int, Int) -> Void

    @MainActor final class Coordinator: NSObject, UIPickerViewDataSource, UIPickerViewDelegate, UIPickerViewAccessibilityDelegate {
        var parent: CyclicTimePicker
        var selectedRows = [0, 0, 0]
        var initialized = false
        var lastRowHeight: CGFloat = 0
        init(_ parent: CyclicTimePicker) { self.parent = parent }
        func period(_ component: Int) -> Int { component == 0 ? (parent.twelveHour ? 12 : 24) : 60 }
        func middleRow(_ value: Int, component: Int) -> Int { period(component) * 15 + value }
        func values() -> [Int] { [parent.time.hour % period(0), parent.time.minute, parent.time.second] }
        func numberOfComponents(in pickerView: UIPickerView) -> Int { 3 }
        func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int { period(component) * 31 }
        func pickerView(_ pickerView: UIPickerView, widthForComponent component: Int) -> CGFloat { pickerView.bounds.width / 3 }
        func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat { parent.rowHeight }
        func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
            var value = row % period(component)
            if component == 0 && parent.twelveHour && value == 0 { value = 12 }
            return String(format: "%02d", value)
        }
        func pickerView(_ pickerView: UIPickerView, attributedTitleForRow row: Int, forComponent component: Int) -> NSAttributedString? {
            NSAttributedString(string: self.pickerView(pickerView, titleForRow: row, forComponent: component)!, attributes: [
                .foregroundColor: UIColor(red: 0.10, green: 0.10, blue: 0.09, alpha: 1),
                .font: UIFont.monospacedDigitSystemFont(ofSize: parent.rowHeight * 25 / 38, weight: .regular)
            ])
        }
        func pickerView(_ pickerView: UIPickerView, accessibilityLabelForComponent component: Int) -> String? { ["Hour", "Minute", "Second"][component] }
        func pickerView(_ pickerView: UIPickerView, accessibilityHintForComponent component: Int) -> String? { "Wraps in both directions without changing other time fields." }
        func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
            let value = TimeWheelMath.value(forRow: row, period: period(component))
            selectedRows[component] = row
            parent.onSelection(component, value)
            // Remain far from either physical end without changing the visible value.
            let centered = middleRow(row % period(component), component: component)
            pickerView.selectRow(centered, inComponent: component, animated: false)
            selectedRows[component] = centered
        }
        func synchronize(_ picker: UIPickerView) {
            if lastRowHeight != parent.rowHeight {
                lastRowHeight = parent.rowHeight
                picker.reloadAllComponents()
            }
            for (component, value) in values().enumerated() {
                if !initialized || picker.selectedRow(inComponent: component) % period(component) != value {
                    let row = middleRow(value, component: component)
                    picker.selectRow(row, inComponent: component, animated: false)
                    selectedRows[component] = row
                }
            }
            initialized = true
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIPickerView {
        let picker = UIPickerView()
        picker.dataSource = context.coordinator; picker.delegate = context.coordinator
        picker.overrideUserInterfaceStyle = .light
        picker.backgroundColor = .clear
        picker.accessibilityIdentifier = "cyclicTimePicker"
        context.coordinator.synchronize(picker)
        return picker
    }
    func updateUIView(_ picker: UIPickerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.synchronize(picker)
    }
}
