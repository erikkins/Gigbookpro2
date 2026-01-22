import SwiftUI

/// Modal view for adding or editing a PDF annotation
struct AnnotationEditorView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var annotationService: AnnotationService

    let pageIndex: Int
    let relativeX: CGFloat
    let relativeY: CGFloat
    let existingAnnotation: PDFAnnotation?

    @State private var text: String = ""
    @State private var selectedColor: AnnotationColor = .yellow
    @State private var selectedFontSize: AnnotationFontSize = .small
    @State private var isBold: Bool = false

    init(annotationService: AnnotationService,
         pageIndex: Int,
         relativeX: CGFloat,
         relativeY: CGFloat,
         existingAnnotation: PDFAnnotation? = nil) {
        self.annotationService = annotationService
        self.pageIndex = pageIndex
        self.relativeX = relativeX
        self.relativeY = relativeY
        self.existingAnnotation = existingAnnotation

        // Initialize state from existing annotation
        if let existing = existingAnnotation {
            _text = State(initialValue: existing.text)
            _selectedColor = State(initialValue: existing.color)
            _selectedFontSize = State(initialValue: existing.fontSize)
            _isBold = State(initialValue: existing.isBold)
        }
    }

    var body: some View {
        NavigationView {
            Form {
                Section("Note") {
                    TextEditor(text: $text)
                        .frame(minHeight: 80, maxHeight: 120)
                }

                Section("Style") {
                    // Font size picker
                    HStack {
                        Text("Size")
                            .foregroundColor(.secondary)
                        Spacer()
                        Picker("Size", selection: $selectedFontSize) {
                            ForEach(AnnotationFontSize.allCases) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }

                    // Bold toggle
                    Toggle(isOn: $isBold) {
                        HStack {
                            Text("Bold")
                            Text("B")
                                .font(.body.bold())
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(AnnotationColor.allCases) { color in
                            colorButton(for: color)
                        }
                    }
                    .padding(.vertical, 8)
                }

                if existingAnnotation != nil {
                    Section {
                        Button(role: .destructive) {
                            deleteAnnotation()
                        } label: {
                            Label("Delete Annotation", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existingAnnotation == nil ? "Add Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAnnotation()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private func colorButton(for color: AnnotationColor) -> some View {
        Button {
            selectedColor = color
        } label: {
            ZStack {
                Circle()
                    .fill(color.uiColor)
                    .frame(width: 36, height: 36)

                if selectedColor == color {
                    Circle()
                        .strokeBorder(Color.primary, lineWidth: 3)
                        .frame(width: 40, height: 40)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.displayName)
    }

    private func saveAnnotation() {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        if var existing = existingAnnotation {
            existing.text = trimmedText
            existing.color = selectedColor
            existing.fontSize = selectedFontSize
            existing.isBold = isBold
            annotationService.updateAnnotation(existing)
        } else {
            let annotation = PDFAnnotation(
                pageIndex: pageIndex,
                relativeX: relativeX,
                relativeY: relativeY,
                text: trimmedText,
                color: selectedColor,
                fontSize: selectedFontSize,
                isBold: isBold
            )
            annotationService.addAnnotation(annotation)
        }

        dismiss()
    }

    private func deleteAnnotation() {
        if let existing = existingAnnotation {
            annotationService.deleteAnnotation(existing)
        }
        dismiss()
    }
}
