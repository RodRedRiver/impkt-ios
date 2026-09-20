import SwiftUI

/// Who the app thinks you are, what it has stored, and what leaves the phone.
///
/// Every value on this screen is read from the page and none of it is kept here. The
/// page is where it is entered, it has to work as a web page with no app around it,
/// and two copies of a weight is one copy too many. So this tab reads and shows; the
/// one thing it writes is the button at the bottom that throws the lot away.
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

    var body: some View {
        NavigationView {
            List {
                if let snap = snap, snap.activated {
                    you(snap)
                    code(snap)
                    profile(snap)
                    sent(snap)
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
                if let snap = snap, snap.activated { clear() }
            }
            .onCanvas()
            .navigationTitle("Profile")
            .onAppear(perform: refresh)
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

    private func profile(_ snap: PageStorage.Snapshot) -> some View {
        Section {
            if let m = snap.measures {
                row("Weight", weight(m))
                row("Height", height(m))
                row("Reach", reach(m))
                row("Stance", stance(m))
                row("Gloves", gloves(m))
                row("Level", level(m))
            } else {
                Text("Not filled in yet. The Test tab asks for it on the screen after your "
                     + "briefing, and until then the numbers have nothing to be compared "
                     + "against.")
                    .font(.footnote).foregroundColor(.secondary)
            }
            Text("Change any of it on the Test tab: your briefing, then Next. None of it is "
                 + "asked for its own sake, and what each answer is for is written on that "
                 + "screen.")
                .font(.caption).foregroundColor(.secondary)
        } header: {
            Text("Your profile")
        }
    }

    private func sent(_ snap: PageStorage.Snapshot) -> some View {
        Section {
            Text("The profile and the code stay on this phone and nothing is sent while you "
                 + "fill them in. When you finish a drill, that drill goes to our database "
                 + "and nowhere else, and it carries a copy of this: your name, your gym, "
                 + "your serial, what the drill asked for and every punch in it. That is "
                 + "the whole of what we send.")
                .font(.footnote).foregroundColor(.secondary)
            if snap.outbox > 0 {
                Text(snap.outbox == 1
                     ? "One finished drill has not reached us yet. It goes up on its own the "
                       + "next time the page has a connection."
                     : "\(snap.outbox) finished drills have not reached us yet. They go up on "
                       + "their own the next time the page has a connection.")
                    .font(.caption).foregroundColor(.secondary)
            }
        } header: {
            Text("What leaves this phone")
        }
    }

    private func about() -> some View {
        Section {
            row("App", Self.appVersion)
            row("Firmware in this app", Updater.bundledVersion)
            Text("The firmware is bundled with the app, so a wrap updated from the Update "
                 + "tab ends up on the version named here and there is one answer to what "
                 + "is on your wraps.")
                .font(.caption).foregroundColor(.secondary)
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
    /// `units` changes nothing but these six lines. The two conversions are the page's
    /// own, to the rounding: a weight that reads 159 lb on one screen and 160 on the
    /// next is a bug report about a scale.
    private func weight(_ m: PageStorage.Measures) -> String {
        guard let kg = m.weightKg, kg > 0 else { return "Not set" }
        if metric(m) { return "\(Int(kg.rounded())) kg" }
        return "\(Int((kg * 2.2046226).rounded())) lb"
    }

    private func height(_ m: PageStorage.Measures) -> String {
        guard let cm = m.heightCm, cm > 0 else { return "Not set" }
        return metric(m) ? "\(Int(cm.rounded())) cm" : feet(cm)
    }

    private func reach(_ m: PageStorage.Measures) -> String {
        guard let cm = m.reachCm, cm > 0 else {
            // Not an omission. Reach is the one optional answer, and when it is left
            // out the page uses height in its place, so saying that is more use than
            // saying "not set" on a line that is being used anyway.
            guard let h = m.heightCm, h > 0 else { return "Not set" }
            return metric(m) ? "About \(Int(h.rounded())) cm, from your height"
                             : "About \(feet(h)), from your height"
        }
        return metric(m) ? "\(Int(cm.rounded())) cm" : feet(cm)
    }

    private func stance(_ m: PageStorage.Measures) -> String {
        switch m.stance {
        case "orthodox": return "Orthodox"
        case "southpaw": return "Southpaw"
        case "switch":   return "Switch"
        default:         return "Not set"
        }
    }

    private func gloves(_ m: PageStorage.Measures) -> String {
        guard let oz = m.gloveOz, oz > 0 else { return "Not set" }
        return "\(Int(oz)) oz"
    }

    /// The words the setup screen offers, not the values it stores, so the two screens
    /// say the same thing about the same pilot.
    private func level(_ m: PageStorage.Measures) -> String {
        switch m.level {
        case "new":      return "First year"
        case "club":     return "Training"
        case "amateur":  return "Amateur"
        case "pro":      return "Professional"
        default:         return "Not set"
        }
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
        }
    }
}
