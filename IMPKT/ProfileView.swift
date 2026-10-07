import SwiftUI

/// Who the app thinks you are, what it has stored, and what leaves the phone.
///
/// Every value on this screen is read from the page and none of it is kept here, and
/// every change to one is written back through the page. The page is where the profile
/// lives, it has to work as a web page with no app around it, and two copies of a
/// weight is one copy too many.
///
/// Written back through the page's own controls, not to its storage. Every number in
/// here is a term in a force estimate, and a value that arrives out of range should
/// come back clamped rather than stored: so a change is sent as a patch, the page
/// applies it to the sliders the setup screen uses, and what comes back is what is
/// stored. See PageControl.saveProfile. Which means this screen shows the stored value
/// and never its own idea of one.
///
/// Which makes it the answer to three questions that otherwise need a drill started to
/// get at: what is my code, what did I put in the profile, and what exactly do you
/// send. The last one is on the page too, under the profile, and it is repeated here
/// because the place somebody looks for it is a screen called Profile.
struct ProfileView: View {

    @State private var snap: PageStorage.Snapshot?
    /// Whether the page has been asked yet. Before the first answer the screen is
    /// blank because nothing has been read, and after it a blank screen means
    /// something, so the two are not allowed to look the same.
    @State private var asked = false
    @State private var clearing = false

    /// The three sliders, in the units the page holds them in, which are metric. A
    /// slider needs somewhere to write while it is being dragged, and telling the page
    /// about every intermediate value would be a hundred saves per drag, so these hold
    /// the drag and the page is told when the finger comes off.
    @State private var weightKg = 78.0
    @State private var heightCm = 178.0
    @State private var reachCm = 178.0
    /// The reach slider's "not set" notch, which is where most people leave it: the page
    /// then works reach out from height. A switch here rather than a notch at one end of
    /// a slider, because a native control has room to say what it is.
    @State private var reachEstimated = true
    /// Set when the page would not save, which on a phone means storage is full.
    @State private var saveFailed = false

    var body: some View {
        NavigationView {
            List {
                if let snap = snap, snap.activated {
                    you(snap)
                    code(snap)
                    profile(snap)
                } else {
                    Section {
                        Text(asked
                             ? "Nothing yet. Enter your code on the Test tab and this fills "
                               + "itself in: the profile is stored by the page, and the page "
                               + "has not been past its front door on this phone."
                             : "Reading the page.")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                about()
                privacy()
                if let snap = snap, snap.activated { clear() }
            }
            .onCanvas()
            .navigationTitle("Profile")
            .onAppear {
                // Cleared on arrival rather than on the way out, so a failure is still
                // on screen when it happens and gone by the next visit.
                saveFailed = false
                refresh()
            }
            .alert("Clear your profile and code?", isPresented: $clearing) {
                Button("Clear", role: .destructive) {
                    PageStorage.clearProfile { ok in
                        // Emptied on what was just done rather than on what the page
                        // would answer: it is reloading, and a read this instant still
                        // catches the briefing it is about to throw away. The second
                        // read is the one that reports what is actually there.
                        if ok { self.snap = nil }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.refresh()
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("The Test tab goes back to asking for a code, and you will need yours "
                   + "to get back in: it is the only way into the page and we cannot "
                   + "recover it. Finished drills that have not reached us yet are kept, "
                   + "and so is which wrap is on which hand.")
            }
        }
    }

    // MARK: - the sections

    private func you(_ snap: PageStorage.Snapshot) -> some View {
        Section {
            row("Name", snap.name)
            row("Gym", snap.gym)
            row("Your pair", snap.serial)
        } header: {
            Text("You")
        }
    }

    private func code(_ snap: PageStorage.Snapshot) -> some View {
        Section {
            if snap.code.isEmpty {
                Text("Not stored on this phone, so the Test tab will ask for it again the "
                     + "next time the app starts.")
                    .font(.footnote).foregroundColor(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Code").font(.footnote)
                    Spacer(minLength: 12)
                    Text(snap.code)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            Text("It is the only way back into the page and we cannot recover it. Keep a "
                 + "copy somewhere that is not this phone.")
                .font(.caption).foregroundColor(.secondary)
        } header: {
            Text("Your code")
        }
    }

    @ViewBuilder private func profile(_ snap: PageStorage.Snapshot) -> some View {
        Section {
            if let m = snap.measures {
                Picker("Units", selection: unitsPick(m)) {
                    Text("Metric").tag("metric")
                    Text("Pounds and feet").tag("imperial")
                }
                .pickerStyle(.segmented)

                slider("Weight", weightText(m), $weightKg, 35...160, 0.5) {
                    save(["weightKg": weightKg])
                }
                slider("Height", lengthText(heightCm, m), $heightCm, 140...215, 1) {
                    save(["heightCm": heightCm])
                }

                // Reach is the one optional answer, so it gets the switch and the slider
                // only appears once somebody has one to give. 150 to 225 and not 0 to
                // 225: the slider's own range is the range of a reach, and "I have not
                // measured it" is the switch above it rather than one end of it.
                Toggle("Work reach out from my height", isOn: estimatePick())
                    .font(.footnote)
                if reachEstimated {
                    row("Reach", reachFromHeight(m))
                } else {
                    slider("Reach", lengthText(reachCm, m), $reachCm, 150...225, 1) {
                        save(["reachCm": reachCm])
                    }
                }

                Picker("Stance", selection: word(m.stance, or: "orthodox") { ["stance": $0] }) {
                    Text("Orthodox").tag("orthodox")
                    Text("Southpaw").tag("southpaw")
                    Text("Switch").tag("switch")
                }
                Picker("Gloves", selection: ounces(m)) {
                    ForEach([8, 10, 12, 14, 16], id: \.self) { oz in
                        Text("\(oz) oz").tag(oz)
                    }
                }
                Picker("Level", selection: word(m.level, or: "club") { ["level": $0] }) {
                    Text("First year").tag("new")
                    Text("Training").tag("club")
                    Text("Amateur").tag("amateur")
                    Text("Professional").tag("pro")
                }
            } else {
                Text("Not filled in yet. The Test tab asks for it on the screen after your "
                     + "briefing, and until then the numbers have nothing to be compared "
                     + "against.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Text(saveFailed
                 ? "That change was not saved. The page could not write to this phone's "
                   + "storage, which usually means it is full."
                 : "Changing any of it here changes it on the Test tab, because there is "
                   + "one profile and the page holds it. None of it is asked for its own "
                   + "sake, and what each answer is for is written on the setup screen.")
                .font(.caption).foregroundColor(saveFailed ? .impktRed : .secondary)
        } header: {
            Text("Your profile")
        }
    }

    /// A labelled slider with the stored value read out above it, and the page told once,
    /// when the finger comes off. Dragging writes to the binding and nothing else: a save
    /// per frame would be a hundred round trips to the page for one weight.
    private func slider(_ key: String, _ shown: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ step: Double,
                        done: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(key)
                Spacer(minLength: 12)
                Text(shown).foregroundColor(.secondary)
            }
            .font(.footnote)
            // The system slider, deliberately: it is the one Apple builds and keeps current, so it draws the
            // iOS 26 thumb and track on its own and nothing here needs redrawing when the system moves on.
            Slider(value: value, in: range, step: step) { editing in
                if !editing { done() }
            }
            .tint(.impktRed)
        }
    }

    // MARK: - the bindings
    //
    // Every one of these reads the stored value and writes a patch, so what a control
    // shows is what the page has rather than what was last touched here. A picker that
    // kept its own selection would sit there showing southpaw after a save the page
    // refused.

    private func unitsPick(_ m: PageStorage.Measures) -> Binding<String> {
        Binding(get: { metric(m) ? "metric" : "imperial" },
                set: { save(["units": $0]) })
    }

    private func word(_ stored: String?, or fallback: String,
                      patch: @escaping (String) -> [String: Any]) -> Binding<String> {
        Binding(get: { stored ?? fallback }, set: { save(patch($0)) })
    }

    private func ounces(_ m: PageStorage.Measures) -> Binding<Int> {
        Binding(get: { Int(m.gloveOz ?? 16) }, set: { save(["gloveOz": $0]) })
    }

    /// Off sends the reach the slider is on, on sends zero, which is the page's own way
    /// of spelling "not answered".
    private func estimatePick() -> Binding<Bool> {
        Binding(get: { reachEstimated },
                set: { on in
                    reachEstimated = on
                    save(["reachCm": on ? 0 : reachCm])
                })
    }

    /// The privacy policy, read in the app. It is one document, Resources/privacy.html, and the
    /// sign-up screen shows the same file, so what a pilot accepted is what they can read here.
    private func privacy() -> some View {
        Section {
            NavigationLink(destination: PolicyView()
                .navigationTitle("Privacy policy")
                .navigationBarTitleDisplayMode(.inline)) {
                Text("Privacy policy").font(.footnote)
            }
        }
    }

    private func about() -> some View {
        Section {
            row("App", Self.appVersion)
            row("Firmware in this app", Updater.bundledVersion)
        } header: {
            Text("This build")
        }
    }

    private func clear() -> some View {
        Section {
            Button("Clear my profile and code", role: .destructive) { clearing = true }
                .font(.footnote)
            Text("This is what the page means by clearing the stored data. It empties this "
                 + "phone, not our copy of anything already sent.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    // MARK: - values

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key)
            Spacer(minLength: 12)
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
        .font(.footnote)
    }

    /// Metric is what the page stores and imperial is a way of reading it, which is why
    /// `units` changes nothing but these three lines. The two conversions are the page's
    /// own, to the rounding: a weight that reads 159 lb on one screen and 160 on the
    /// next is a bug report about a scale.
    ///
    /// Read off the slider and not out of storage, because the slider is what is moving:
    /// a readout that waited for the save would sit still under a finger that was
    /// dragging it, which reads as a broken control rather than as a careful one.
    private func weightText(_ m: PageStorage.Measures) -> String {
        if metric(m) { return "\(Int(weightKg.rounded())) kg" }
        return "\(Int((weightKg * 2.2046226).rounded())) lb"
    }

    private func lengthText(_ cm: Double, _ m: PageStorage.Measures) -> String {
        metric(m) ? "\(Int(cm.rounded())) cm" : feet(cm)
    }

    /// What the page will use for reach when nobody has given one. Not an omission and
    /// not a blank: the estimate is in the force numbers either way, so it is worth
    /// reading next to the switch that chose it.
    private func reachFromHeight(_ m: PageStorage.Measures) -> String {
        guard let h = m.heightCm, h > 0 else { return "From your height" }
        return metric(m) ? "About \(Int(h.rounded())) cm, from your height"
                         : "About \(feet(h)), from your height"
    }

    private func metric(_ m: PageStorage.Measures) -> Bool { m.units != "imperial" }

    /// Feet and inches with the page's own prime marks, and the page's own rounding:
    /// to the nearest inch first, so 5′ 12″ cannot happen.
    private func feet(_ cm: Double) -> String {
        let total = Int((cm / 2.54).rounded())
        return "\(total / 12)′ \(total % 12)″"
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func refresh() {
        PageStorage.read { snap in
            self.snap = snap
            self.asked = true
            if let m = snap?.measures { self.adopt(m) }
        }
    }

    /// Sends one field and takes what comes back as the truth.
    ///
    /// What comes back is the whole profile as stored, which is not always what was
    /// asked for: the page clamps a number to the slider's range and refuses a word it
    /// does not offer. Adopting the answer rather than the request is what makes this
    /// screen show the profile instead of showing the last thing somebody touched.
    private func save(_ patch: [String: Any]) {
        PageControl.saveProfile(patch) { stored in
            guard let stored = stored else {
                self.saveFailed = true
                // Back to what is actually there, so the controls stop showing a change
                // that did not happen.
                self.refresh()
                return
            }
            self.saveFailed = false
            self.snap?.measures = stored
            self.adopt(stored)
        }
    }

    /// Puts the sliders where the stored profile says they are.
    private func adopt(_ m: PageStorage.Measures) {
        if let kg = m.weightKg, kg > 0 { weightKg = min(160, max(35, kg)) }
        if let cm = m.heightCm, cm > 0 { heightCm = min(215, max(140, cm)) }
        reachEstimated = (m.reachCm ?? 0) <= 0
        // A pilot who has never given a reach still needs the slider to start somewhere
        // sensible if they turn the switch off, and the sensible place is the page's own
        // estimate, which is their height.
        let reach = (m.reachCm ?? 0) > 0 ? m.reachCm! : (m.heightCm ?? 178)
        reachCm = min(225, max(150, reach))
    }
}

