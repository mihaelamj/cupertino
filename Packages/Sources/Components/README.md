#  Accesability Notes

- Add hints 
- If SwiftUI cann not determine the type of the component automatically, add description and hints
- Add description for images

## TEXT

- Use system text styles to automatically support Dynamic Type (font scaling for users with larger text settings). Avoid fixed-size fonts (like *.font(.system(size: 14))*) unless absolutely necessary — they ignore user preferences.

Text("Hello World!")
    .font(.body)

- For plain Text, the displayed string is automatically used as the accessibility label.
You only need to add a label if the visible text doesn’t match what should be spoken.

Text("💬")
    .accessibilityLabel("Messages")

- If text is purely decorative or redundant (e.g., repeated visually elsewhere), hide it from accessibility tools.

Text("—")
    .accessibilityHidden(true)

- You can add traits to elements, for example we can emphasize that a certain text element is a header and VO will read this so the user knows as well.

Text("This is a header!")
    .accessibilityAddTraits(.isHeader)

- If we have lements in a stack we can assign order in which they are read to the user. Higher number passed equals higher priority.

Text("This text if very important")
    .accessibilitySortPriority(1)


## IMAGE

- Similiar to the Text, Images can also be hidden if they are decorative or you can add a accessibility label to them to describe what is being shown.

- Special mention here goes to the SF Symbols images, they have built-in accessibility names that VoiceOver reads automatically.
Only override if the meaning in your app differs from the default.


## BUTTON

- The text or label inside a Button should clearly describe its action — what happens when tapped. VoiceOver automatically uses the button’s text as the accessibility label, so you usually don’t need to set it manually unless the button’s content is non-text (like an icon).

- If a button contains only an image, you must provide a label that describes its action.

Button(action: deleteItem) {
    Image(systemName: "trash")
}
    .accessibilityLabel("Delete item")

- You can also add accessibility hints to a button, they explain what happens when you tap the button.

Button(action: deleteItem) {
    Image(systemName: "trash")
}
    .accessibilityLabel("Delete item")
    .accessibilityHint("When you press this button item will be deleted.")

- If a button is disabled, the VO will read it out as *"Dimmed"*.

- If a button has both an image and text, combine them into a single accessible element. Using Label is the recommended approach in SwiftUI for icon + text buttons.

Button(action: shareContent) {
    Label("Share", systemImage: "square.and.arrow.up")
}

- When making a custom button we have to add the accessibility by our selves, marking it with *.accessibilityElement()*

ZStack {
    Circle()
        .fill(Color.blue)
    Image(systemName: "plus")
        .foregroundColor(.white)
}
.accessibilityElement()
.accessibilityLabel("Add new contact")
.accessibilityAddTraits(.isButton)
.onTapGesture { addContact() }


## TEXTFIELD

- Each TextField must have a label that clearly indicates what the user should enter. VoiceOver will automatically use the placeholder text as the field’s label if no explicit label is provided.
However, it’s best practice to associate the field with a visible Text label for clarity.

- For secure fields, like passwords, use *SecureField* and VO will read them as such.

- Use *.accessibilityHint* if the field’s purpose or behavior needs clarification.

TextField("Search", text: $query)
    .accessibilityHint("Type a keyword and results will update automatically")

- You can communicate that a field is required.

TextField("Full Name", text: $name)
    .accessibilityHint("Required field")


## LIST

### Example ###

*List(users) { user in
    HStack {
        Image(uiImage: user.avatar)
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)
        VStack(alignment: .leading) {
            Text(user.name)
            Text(user.role)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    .accessibilityElement(children: .combine)
}*

- Provide Clear Labels for Each Row, every row (cell) should make sense on its own, since VoiceOver reads each item individually.

- If a row contains multiple elements (e.g., image + text + button), group them into a single accessibility element so VoiceOver reads them as one coherent item by using the *.accessibilityElement(children: .combine)*, so they above example would be read as "John, History Teacher". 

- Other than *.combine* we have *.ignore* that ignores child elements, here you can add your own label that you want to be read out.

- Lastly we have *.automatic* which is used by default and it is mostly used for simple UI layout.
