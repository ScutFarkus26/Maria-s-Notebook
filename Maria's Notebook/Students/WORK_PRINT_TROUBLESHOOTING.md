# Work Print Feature - Troubleshooting Guide

## Common Issues and Solutions

### Issue: "Cannot find 'WorkPrintButton' in scope"

**Problem**: Xcode can't find the WorkPrintButton component.

**Solutions**:
1. Ensure `WorkPrintButton.swift` is added to your target
   - In Xcode, select the file
   - Check the Target Membership in File Inspector
   - Ensure your app target is checked

2. Import SwiftUI at the top of your file:
   ```swift
   import SwiftUI
   import SwiftData
   ```

3. Make sure the file is saved (⌘S)

4. Clean build folder (⌘⇧K) and rebuild (⌘B)

---

### Issue: Print button is grayed out/disabled

**Problem**: The print button appears but can't be clicked.

**Cause**: The button automatically disables when `workItems` array is empty.

**Solutions**:
1. Check your work items array:
   ```swift
   // Add temporary debugging
   var body: some View {
       List(work) { item in
           // ...
       }
       .onAppear {
           print("Work items count: \(work.count)")
       }
   }
   ```

2. Verify your query is fetching data:
   ```swift
   @Query private var work: [WorkModel]
   
   // Make sure this returns items
   // If using a predicate, verify it's not filtering everything out
   ```

3. Check if you're passing the right array:
   ```swift
   // Make sure you're passing work, not an empty array
   WorkPrintButton(
       workItems: work,  // ← Should not be empty
       // ...
   )
   ```

---

### Issue: "Cannot find 'WorkPrintView' in scope"

**Problem**: WorkPrintButton can't find WorkPrintView.

**Solutions**:
1. Ensure both files are in your target:
   - `WorkPrintView.swift`
   - `WorkPrintButton.swift`

2. Check that WorkPrintView is properly defined (not private):
   ```swift
   struct WorkPrintView: View {  // ← Should not be 'private'
       // ...
   }
   ```

3. Clean and rebuild the project

---

### Issue: Nothing happens when clicking print button

**Problem**: Button is enabled but clicking does nothing.

**Solutions**:
1. Check console for errors:
   - Open Debug Console (⌘⇧Y)
   - Look for runtime errors or warnings

2. Verify the sheet modifier is present:
   ```swift
   // WorkPrintButton should have this internally
   .sheet(isPresented: $showPrintSheet) {
       WorkPrintSheet(/* ... */)
   }
   ```

3. Check that you're not in a preview:
   - Print functionality may not work in Xcode previews
   - Run on simulator or device instead

4. For macOS, check window hierarchy:
   - Print may fail if there's no key window
   - Ensure app is frontmost

---

### Issue: "Cannot find 'AppColors' in scope"

**Problem**: Print view references AppColors which doesn't exist.

**Solutions**:
1. Find your app's color utility and use it:
   ```swift
   // In WorkPrintView.swift, find:
   AppColors.color(forSubject: lesson.subject)
   
   // Replace with your color utility:
   YourColorHelper.color(forSubject: lesson.subject)
   ```

2. Or use simple colors:
   ```swift
   // Replace with:
   Color.blue
   // or
   Color.accentColor
   ```

---

### Issue: Students not showing in print view

**Problem**: Print preview shows no students or incomplete data.

**Cause**: Student IDs in WorkModel don't match Student IDs.

**Solutions**:
1. Verify student ID format:
   ```swift
   // WorkModel stores studentID as String
   // Should be UUID formatted: "12345678-1234-1234-1234-123456789012"
   print("Work studentID: \(work.studentID)")
   print("Student ID: \(student.id.uuidString)")
   ```

2. Check student query is fetching:
   ```swift
   @Query private var students: [Student]
   
   var body: some View {
       // ...
       .onAppear {
           print("Students count: \(students.count)")
       }
   }
   ```

3. Verify UUID conversion:
   ```swift
   // In WorkPrintView's groupedWork, check:
   guard let studentID = UUID(uuidString: studentIDString),
         let student = students.first(where: { $0.id == studentID }) else {
       print("Failed to find student for ID: \(studentIDString)")
       return nil
   }
   ```

---

### Issue: Lessons not showing in print view

**Problem**: Print shows "Lesson" instead of actual lesson names.

**Solutions**:
1. Similar to students, verify lesson ID format:
   ```swift
   print("Work lessonID: \(work.lessonID)")
   print("Lesson ID: \(lesson.id.uuidString)")
   ```

2. Check lesson query:
   ```swift
   @Query private var lessons: [Lesson]
   
   var body: some View {
       // ...
       .onAppear {
           print("Lessons count: \(lessons.count)")
       }
   }
   ```

---

### Issue: "Cannot convert value of type 'WorkKind' to expected argument type 'String'"

**Problem**: WorkKind enum doesn't have displayName.

**Solutions**:
1. Add displayName to WorkKind:
   ```swift
   extension WorkKind {
       var displayName: String {
           switch self {
           case .practiceLesson: return "Practice"
           case .followUp: return "Follow Up"
           case .research: return "Research"
           case .report: return "Report"
           case .choice: return "Choice"
           }
       }
   }
   ```

2. Or use rawValue:
   ```swift
   // In WorkPrintView, replace:
   kind.displayName
   // with:
   kind.rawValue
   ```

---

### Issue: Print preview shows but is blank/empty

**Problem**: Print sheet appears but content is white/blank.

**Solutions**:
1. Check your data is being passed:
   ```swift
   WorkPrintSheet(
       workItems: displayedWork,
       students: students,
       lessons: lessons,
       filterDescription: filterDescription,
       sortDescription: sortDescription
   )
   // Add breakpoint or print to verify arrays aren't empty
   ```

2. Verify modelContext is available:
   ```swift
   // WorkPrintView needs modelContext
   @Environment(\.modelContext) private var modelContext
   ```

3. Check groupedWork computation:
   ```swift
   // In WorkPrintView, add debugging:
   private var groupedWork: [(Student, [WorkModel])] {
       let result = /* ... computed value ... */
       print("Grouped work count: \(result.count)")
       return result
   }
   ```

---

### Issue: iOS print dialog doesn't appear

**Problem**: On iOS, clicking print doesn't show print dialog.

**Solutions**:
1. Check Info.plist for required keys:
   ```xml
   <key>NSPrintingEnabled</key>
   <true/>
   ```

2. Verify you're running on device or simulator, not preview

3. Check console for print controller errors:
   ```swift
   // In WorkPrintSheet's presentPrint:
   printController.present(animated: true) { _, completed, error in
       if let error = error {
           print("Print error: \(error)")
       }
   }
   ```

---

### Issue: macOS print preview window is blank

**Problem**: On macOS, print preview opens but shows blank page.

**Solutions**:
1. Check NSHostingView sizing:
   ```swift
   let hostingView = NSHostingView(rootView: printView.frame(width: 612, height: 792))
   hostingView.frame = CGRect(x: 0, y: 0, width: 612, height: 792)
   // Frame must match content frame
   ```

2. Verify window hierarchy:
   ```swift
   // Ensure there's a key window
   guard let window = NSApp.keyWindow else {
       print("No key window available")
       return
   }
   ```

---

### Issue: Print view cuts off content

**Problem**: Some content is cut off in print.

**Solutions**:
1. Check if you have many items:
   ```swift
   // The current layout fits ~8-12 items
   // For more, consider pagination or filtering
   print("Printing \(workItems.count) items")
   ```

2. Reduce font sizes slightly in WorkPrintView.swift:
   ```swift
   // Find font calls like:
   .font(.system(size: 12))
   // Try reducing to:
   .font(.system(size: 11))
   ```

3. Add pagination (advanced):
   ```swift
   // Split into multiple pages
   // This requires custom PDF generation
   ```

---

### Issue: Colors don't appear in print

**Problem**: Subject color dots don't show.

**Solutions**:
1. Check if AppColors is returning valid colors:
   ```swift
   let color = AppColors.color(forSubject: lesson.subject)
   print("Subject color: \(color)")
   ```

2. For B&W printers, this is expected:
   - Colors print as grayscale automatically
   - Circle shape still shows

3. If colors never show, check Circle view:
   ```swift
   Circle()
       .fill(AppColors.color(forSubject: lesson.subject))
       .frame(width: 6, height: 6)
   // Try increasing size for testing:
   .frame(width: 20, height: 20)
   ```

---

### Issue: "Ambiguous use of 'sheet(item:)'"

**Problem**: Multiple sheet modifiers causing conflict.

**Solutions**:
1. Use `isPresented` variant:
   ```swift
   .sheet(isPresented: Binding(
       get: { showPrintSheet },
       set: { showPrintSheet = $0 }
   )) {
       WorkPrintSheet(/* ... */)
   }
   ```

2. Ensure only one sheet per view hierarchy level

---

### Issue: Performance is slow with many items

**Problem**: Print preview takes long time to appear.

**Solutions**:
1. Limit items for printing:
   ```swift
   private var printableWork: [WorkModel] {
       Array(displayedWork.prefix(50))  // Limit to 50 items
   }
   ```

2. Reduce preview scale:
   ```swift
   // In WorkPrintSheet preview
   .scaleEffect(0.3)  // Reduced from 0.5
   ```

3. Add loading indicator:
   ```swift
   @State private var isGenerating = false
   
   if isGenerating {
       ProgressView("Generating preview...")
   }
   ```

---

### Issue: Filter/sort descriptions are wrong

**Problem**: Print header shows incorrect filter or sort info.

**Solutions**:
1. Verify you're passing correct descriptions:
   ```swift
   WorkPrintButton(
       workItems: work,
       students: students,
       lessons: lessons,
       filterDescription: yourActualFilterDescription,  // ← Check this
       sortDescription: yourActualSortDescription       // ← And this
   )
   ```

2. Update descriptions dynamically:
   ```swift
   private var filterDescription: String {
       // Compute based on current filter state
       switch currentFilter {
       case .all: return "All items"
       case .open: return "Open items only"
       // etc.
       }
   }
   ```

---

## Debugging Checklist

When troubleshooting, check these in order:

- [ ] Both WorkPrintView.swift and WorkPrintButton.swift are in your target
- [ ] You have `import SwiftUI` and `import SwiftData` at the top
- [ ] Your work array has items in it
- [ ] Your students array has items in it
- [ ] Your lessons array has items in it
- [ ] WorkModel studentID and lessonID are valid UUID strings
- [ ] You're testing on simulator/device, not just preview
- [ ] You've cleaned and rebuilt the project
- [ ] Console shows no errors
- [ ] The button appears in the toolbar
- [ ] The button is enabled (not grayed out)

## Still Having Issues?

1. **Start with the minimal example**:
   - Copy `MinimalWorkPrintExample.swift` exactly
   - Get that working first
   - Then adapt to your view

2. **Check the complete example**:
   - `ExampleWorkListViewWithPrint.swift` shows everything working
   - Compare your code to this example
   - Look for differences in structure

3. **Add strategic print statements**:
   ```swift
   // Add these to debug data flow
   print("Work count: \(work.count)")
   print("Students count: \(students.count)")
   print("Lessons count: \(lessons.count)")
   print("Button tapped")
   print("Sheet presenting")
   ```

4. **Verify your model structure**:
   - Check WorkModel has all expected fields
   - Verify Student and Lesson models are correct
   - Ensure relationships are properly set up

## Platform-Specific Issues

### iOS Only

**AirPrint not finding printers**:
- Check WiFi connection
- Ensure printer is AirPrint compatible
- Try "Print to PDF" instead

**Print sheet doesn't dismiss**:
- Check dismiss() is being called in completion handler
- Verify sheet environment is correct

### macOS Only

**Print operation fails silently**:
- Check NSApp.keyWindow exists
- Verify app has foreground focus
- Check Console.app for system errors

**Preview window is tiny**:
- Check frame sizes in NSHostingView creation
- Verify print info margins are reasonable

## Getting Help

If none of these solutions work:

1. Create a minimal reproducible example
2. Note your exact error message
3. Check your SwiftData schema
4. Verify your iOS/macOS version
5. Check if issue is specific to device or simulator

The code is designed to work with standard Swift/SwiftUI/SwiftData - if something isn't working, it's usually a data issue or integration mismatch, not the print code itself.
