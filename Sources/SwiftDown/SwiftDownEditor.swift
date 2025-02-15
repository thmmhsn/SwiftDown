//
//  SwiftDownEditor.swift
//
//
//  Created by Quentin Eude on 16/03/2021.
//

import Down
import SwiftUI
import Combine

#if os(iOS)
  // MARK: - SwiftDownEditor iOS
public struct SwiftDownEditor: UIViewRepresentable {
  private var debounceTime = 0.3
  @Binding var text: String {
    didSet {
      onTextChange(text)
    }
  }

  private(set) var isEditable: Bool = true
  private(set) var theme: Theme = Theme.BuiltIn.defaultDark.theme()
  private(set) var insetsSize: CGFloat = 0
  private(set) var autocapitalizationType: UITextAutocapitalizationType = .sentences
  private(set) var autocorrectionType: UITextAutocorrectionType = .default
  private(set) var keyboardType: UIKeyboardType = .default
  private(set) var hasKeyboardToolbar: Bool = true
  private(set) var textAlignment: TextAlignment = .leading

  public var onTextChange: (String) -> Void = { _ in }
  public var onSelectionChange: (NSRange) -> Void = { _ in }
  let engine = MarkdownEngine()

  public init(
    text: Binding<String>,
    onTextChange: @escaping (String) -> Void = { _ in },
    onSelectionChange: @escaping (NSRange) -> Void = { _ in }
  ) {
    _text = text
    self.onTextChange = onTextChange
    self.onSelectionChange = onSelectionChange
  }

  public func makeUIView(context: Context) -> SwiftDown {
    let swiftDown = SwiftDown(frame: .zero, theme: theme)
    swiftDown.storage.markdowner = { self.engine.render($0, offset: $1) }
    swiftDown.storage.applyMarkdown = { m in Theme.applyMarkdown(markdown: m, with: self.theme) }
    swiftDown.storage.applyBody = { Theme.applyBody(with: self.theme) }

    swiftDown.delegate = context.coordinator
    swiftDown.isEditable = isEditable
    swiftDown.isScrollEnabled = true
    swiftDown.keyboardType = keyboardType
    swiftDown.hasKeyboardToolbar = hasKeyboardToolbar
    swiftDown.autocapitalizationType = autocapitalizationType
    swiftDown.autocorrectionType = autocorrectionType
    swiftDown.textContainerInset = UIEdgeInsets(
      top: insetsSize, left: insetsSize, bottom: insetsSize, right: insetsSize)
    swiftDown.backgroundColor = theme.backgroundColor
    swiftDown.tintColor = theme.tintColor
    swiftDown.textColor = theme.tintColor
    swiftDown.text = text

    return swiftDown
  }

  public func updateUIView(_ uiView: SwiftDown, context: Context) {
    context.coordinator.cancellable?.cancel()
    context.coordinator.cancellable = Timer
      .publish(every: debounceTime, on: .current, in: .default)
      .autoconnect()
      .first()
      .sink { _ in
        let selectedRange = uiView.selectedRange
        uiView.text = text
        uiView.highlighter?.applyStyles()
        uiView.selectedRange = selectedRange
      }
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
}

// MARK: - SwiftDownEditor iOS Coordinator
extension SwiftDownEditor {
  public class Coordinator: NSObject, UITextViewDelegate {
    var cancellable: Cancellable?
    var parent: SwiftDownEditor

    init(_ parent: SwiftDownEditor) {
      self.parent = parent
    }

    public func textViewDidChange(_ textView: UITextView) {
      guard textView.markedTextRange == nil else { return }
      DispatchQueue.main.async {
        self.parent.text = textView.text
      }
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
      guard textView.markedTextRange == nil else { return }
      self.parent.onSelectionChange(textView.selectedRange)
    }
    
    // --- New: Todo and bullet list handling ---
    public func textView(_ textView: UITextView,
                         shouldChangeTextIn range: NSRange,
                         replacementText text: String) -> Bool {
      if text == "\n", let currentLine = currentLine(from: textView, at: range.location) {
        // Try to detect a todo item first:
        if let newTodo = nextTodo(for: currentLine) {
          textView.insertText("\n" + newTodo)
          return false
        }
        // Fallback to the bullet list behavior:
        if let newBullet = nextBullet(for: currentLine) {
          textView.insertText("\n" + newBullet)
          return false
        }
      }
      return true
    }
    
    private func currentLine(from textView: UITextView, at location: Int) -> String? {
      let nsText = textView.text as NSString
      let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
      return nsText.substring(with: lineRange)
    }
    
    private func nextBullet(for currentLine: String) -> String? {
      let pattern = "^\\s*([-*]|\\d+[.])\\s+"
      guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let result = regex.firstMatch(in: currentLine,
                                          options: [],
                                          range: NSRange(location: 0, length: currentLine.utf16.count))
      else {
        return nil
      }
      let bulletStart = (currentLine as NSString).substring(with: result.range)
      if bulletStart.contains(".") {
        if let number = Int(bulletStart.prefix { $0.isNumber }) {
          return "\(number + 1). "
        }
        return nil
      }
      return bulletStart
    }
    
    private func nextTodo(for currentLine: String) -> String? {
      // Look for todo markers like "- [ ]" or "* [ ]"
      let pattern = "^\\s*[-*]\\s*\\[( |x|X)\\]\\s+"
      guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
            let _ = regex.firstMatch(in: currentLine,
                                     options: [],
                                     range: NSRange(location: 0, length: currentLine.utf16.count))
      else {
        return nil
      }
      // Preserve the current indentation:
      if let leadingWhitespaceRange = currentLine.range(of: "^\\s*", options: .regularExpression) {
        let leadingWhitespace = String(currentLine[leadingWhitespaceRange])
        return leadingWhitespace + "- [ ] "
      }
      return "- [ ] "
    }
    // --- End New ---
  }
}

  // MARK: - iOS Specifics modifiers
extension SwiftDownEditor {
  public func autocapitalizationType(_ type: UITextAutocapitalizationType) -> Self {
    var new = self
    new.autocapitalizationType = type
    return new
  }

  public func autocorrectionType(_ type: UITextAutocorrectionType) -> Self {
    var new = self
    new.autocorrectionType = type
    return new
  }

  public func keyboardType(_ type: UIKeyboardType) -> Self {
    var new = self
    new.keyboardType = type
    return new
  }

  public func textAlignment(_ type: TextAlignment) -> Self {
    var new = self
    new.textAlignment = type
    return new
  }

  public func hasKeyboardToolbar(_ hasKeyboardToolbar: Bool) -> Self {
    var editor = self
    editor.hasKeyboardToolbar = hasKeyboardToolbar
    return editor
  }
}
#else
  // MARK: - SwiftDownEditor macOS
  public struct SwiftDownEditor: NSViewRepresentable {
    private var debounceTime = 0.0
    @Binding var text: String {
      didSet {
        onTextChange(text)
      }
    }

    private(set) var isEditable: Bool = true
    private(set) var theme: Theme = Theme.BuiltIn.defaultDark.theme()
    private(set) var insetsSize: CGFloat = 0

    public var onTextChange: (String) -> Void = { _ in }
    public var onSelectionChange: (NSRange) -> Void = { _ in }

    public init(
      text: Binding<String>,
      onTextChange: @escaping (String) -> Void = { _ in },
      onSelectionChange: @escaping (NSRange) -> Void = { _ in }
    ) {
      _text = text
      self.onTextChange = onTextChange
      self.onSelectionChange = onSelectionChange
    }

    public func makeNSView(context: Context) -> SwiftDown {
      let swiftDown = SwiftDown(theme: theme, isEditable: isEditable, insetsSize: insetsSize)
      swiftDown.delegate = context.coordinator
      swiftDown.setupTextView()
      swiftDown.text = text
      return swiftDown
    }

    public func updateNSView(_ nsView: SwiftDown, context: Context) {
      context.coordinator.cancellable?.cancel()
      context.coordinator.cancellable = Timer
        .publish(every: debounceTime, on: .current, in: .default)
        .autoconnect()
        .first()
        .sink { _ in
          let selectedRanges = nsView.selectedRanges
          nsView.text = text
          nsView.applyStyles()
          nsView.selectedRanges = selectedRanges
        }
    }

    public func makeCoordinator() -> Coordinator {
      Coordinator(self)
    }
  }

  // MARK: - SwiftDownEditor Coordinator macOS
extension SwiftDownEditor {
    public class Coordinator: NSObject, NSTextViewDelegate {
      var parent: SwiftDownEditor
      var cancellable: Cancellable?

      init(_ parent: SwiftDownEditor) {
        self.parent = parent
      }

      // Helper Function to Get the Current Line Text
      private func currentLine(from textView: NSTextView, at location: Int) -> String? {
          let nsText = textView.string as NSString
          let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
          return nsText.substring(with: lineRange)
      }

      // Existing bullet list helper
      private func nextBullet(for currentLine: String) -> String? {
        let pattern = "^\\s*([-*]|\\d+[.])\\s+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let result = regex.firstMatch(in: currentLine, options: [], range: NSRange(location: 0, length: currentLine.utf16.count)) else {
          return nil
        }
        
        let bulletStart = (currentLine as NSString).substring(with: result.range)
        
        if bulletStart.contains(".") {
          if let number = Int(bulletStart.prefix { $0.isNumber }) {
            return "\(number + 1). "
          }
          return nil
        }
        return bulletStart
      }
      
      // --- New: Todo list support ---
      private func nextTodo(for currentLine: String) -> String? {
        // Updated regex: trailing whitespace is now optional.
        let pattern = "^\\s*[-*]\\s*\\[(?:\\s|x|X)?\\]\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              regex.firstMatch(in: currentLine,
                               options: [],
                               range: NSRange(location: 0, length: currentLine.utf16.count)) != nil
        else {
          return nil
        }
        // Preserve leading indentation:
        if let leadingWhitespaceRange = currentLine.range(of: "^\\s*", options: .regularExpression) {
          let leadingWhitespace = String(currentLine[leadingWhitespaceRange])
          return leadingWhitespace + "- [ ] "
        }
        return "- [ ] "
      }
      // --- End New ---

      public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
          return
        }
        self.parent.text = textView.string
      }

      public func textView(_ textView: NSTextView,
                           shouldChangeTextIn range: NSRange,
                           replacementString: String?) -> Bool {
        if replacementString == "\n", let currentLine = currentLine(from: textView, at: range.location) {
          // Try todo list first:
          if let newTodo = nextTodo(for: currentLine) {
            textView.insertText("\n" + newTodo)
            return false
          }
          // Fallback to the bullet list behavior:
          if let newBullet = nextBullet(for: currentLine) {
            textView.insertText("\n" + newBullet)
            return false
          }
        }
        return true
      }

      public func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else {
          return
        }
        self.parent.onSelectionChange(textView.selectedRange())
      }
    }
  }

#endif

// MARK: - Common Modifiers
extension SwiftDownEditor {
  public func insetsSize(_ size: CGFloat) -> Self {
    var editor = self
    editor.insetsSize = size
    return editor
  }

  public func theme(_ theme: Theme) -> Self {
    var editor = self
    editor.theme = theme
    return editor
  }

  public func isEditable(_ isEditable: Bool) -> Self {
    var editor = self
    editor.isEditable = isEditable
    return editor
  }

  public func debounceTime(_ debounceTime: Double) -> Self {
     var editor = self
     editor.debounceTime = debounceTime
     return editor
   }
}
