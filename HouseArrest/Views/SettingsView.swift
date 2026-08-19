import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("ha.appearance") private var appearanceRaw = HAAppearance.system.rawValue
    @State private var copied = false

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v.\(version)"
    }

    var body: some View {
        NavigationStack {
            List {
                aboutSection
                appearanceSection
                thanksSection
                debugSection
            }
            .tint(HATheme.accent)
            .listItemTint(HATheme.accent)
            .navigationTitle("Settings")
        }
        .tint(HATheme.accent)
    }

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text("HouseArrest")
                        .font(.headline)
                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(HATheme.secondaryText)
                }
            }
            .padding(.vertical, 4)

            Link(destination: URL(string: "https://github.com/brynts/HouseArrest")!) {
                HStack {
                    Label("GitHub", systemImage: "link")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack {
                Text("Theme")
                Spacer()
                Picker("Theme", selection: $appearanceRaw) {
                    ForEach(HAAppearance.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 220)
            }
        }
    }

    private var thanksSection: some View {
        Section("Special Thanks") {
            Link(destination: URL(string: "https://github.com/forcequitOS/bad_query")!) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("bad_query")
                        Text("forcequitOS")
                            .font(.caption)
                            .foregroundStyle(HATheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var debugSection: some View {
        Section("Debug") {
            NavigationLink {
                LogsView()
            } label: {
                accentLabel("Logs", "terminal.fill")
            }
            Button {
                appModel.copyLogs()
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copied = false
                }
            } label: {
                accentLabel(copied ? "Copied" : "Copy logs", "doc.on.doc")
            }
            .buttonStyle(.plain)
            .disabled(appModel.logLines.isEmpty)
        }
    }

    private var avatar: some View {
        Group {
            if let image = AuthorAvatar.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(HATheme.accent)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func accentLabel(_ title: String, _ icon: String) -> some View {
        Label {
            Text(title).foregroundStyle(HATheme.accent)
        } icon: {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(HATheme.accent)
        }
    }
}

private enum AuthorAvatar {
    static var image: UIImage? {
        UIImage(data: Data(base64Encoded: payload) ?? Data())
    }

    private static let payload = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAoHBwgHBgoICAgLCgoLDhgQDg0NDh0VFhEYIx8lJCIfIiEmKzcvJik0KSEiMEExNDk7Pj4+JS5ESUM8SDc9Pjv/2wBDAQoLCw4NDhwQEBw7KCIoOzs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozv/wAARCACgAKADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDl6KKK8Q/UgooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAoorb0Lwlq3iDD2sAjt84M8vyp+Hr+FNJydkZ1KsKUeabsjEo4FegSeFvCHhpQ3iLWhLN18lW2/+OrljVZ/iF4O0obNH8NtOR0d41TP4nLfpXTHCze+h4lbPcPB2gnL8F/XyOJ2nGcHHrSV2B+M6B9knh228vuv2jn/0Crtp4k8BeL2W3vbH+y7qXhZCAgJ9nXj/AL6FU8I+jMafEFNv34NL1v8A5HBUV0Pirwjd+Gpg5bz7KQ4jnAxg+jeh/nXPZHqK5JRcXZn0FGtCtBTpu6YUUYopGoUUUUAFFFFABRRRQAUUUUAFFFXdH02TV9WttPiOGncKW/ujqT+AzQld2RMpKEXKWyOg8F+FItU8zVtVIj0u2yTvOBIR1yf7o71U8V/Eu71B207QHaw06MbQ8Y2ySjpx/dX0A5/lV/4na7HYwweENL/dW1vGpudp691T/wBmPrkV5p/y2Puo/nXrUqapxsfnuOxs8XVcnt0Q8nLFiSWY5JJyTVZwxDZBdg2NvbH0qxmq0sw3EpggjaSen/161OEaPlU4J9Dz3HP8qFlVXO0l1PXAzUKb5mEcUbzMOgC7v0FXV0PW5lyul3rD/rg2P5UNpDSbO38MfFRtI0dtL1ewOpQxkeQXkXKr/dbIOQO1ag+Lnh+f5LnwpGU9mjb9Coryy50+9scfa7Oe3z0MsZUH86gxS0Y1KUdnY9qsj4A8at9msN2mX7j5I8bCT7DJVvoOa4/W9HudB1WWwusFk5Vx0dT0IrD8F6Pe6z4qsbax3hkmWWSRf+WSKQSx/Lj3Nd78TryC58TpFCQzW0ASQj+8STj8iK5MTTio8y3Po8lxdedb2Um3G3XocfRRRXAfWhRRRQAUUUUAFFFFABXX/DKJZPFu9usds7L9cgfyJrkK6n4cXAg8YQKTgTxPH+mf/Za0pfGjizBN4SpbszkvE073PinVZnOWa8l/IMQP0ArHkIQrITgDIP0Nb3ja1OneMNWikG0faWkH+6/zD+dc4yGU73BOPux+/v7165+dGppPh3VPEPz28Yitc4M0vCn+rfQfia7XTPAOj2eHu1a/lHeXhB9FH9c1u6XZDTtKtbIf8sIlQ/XHP65rMvJbo3ko/wCEos7NAxCwrDGWX2JZjz+FccqkpOydjsjTjFXeptW9vBaoI7aGOFR/DGgUfpUlYVnLcC7i3+J4bqMtgxG3jUv7Bga2pZUhheR3CKiklj0FYtWNk7oJY45omilRZI2GGRxkEe4rg9L+GGpa7rt4sG2y0qG5ZBcPzkA9EXvjpzgV0AsWm+a51fXJm/6YwyQoPoFT+praSX/i3OveRLN+6nZNz7lfIEec5wc9c1vSvC7MnFVZxh3aX3lS41nQfAemPo/heNZ71uJrondhvVm/iPoBwK4GSR5pXllcvI7FmZjksT1JpvSiuOpVlUd2fb4PBUsJDlhv1fcKKKKzO4KKKKACiiigAooooAK6b4e2aXfjC2L5xAjTDB7gYH865mt3wZqaaT4ps7iVtsTkxSE9gwxn88VdOymrnLjFKWHmob2Z0Wt2dprGsXeq3Olx3sgka3jjIX5Y42K5weCxIJ/EDtXJal4VjfULC90aJnsrmdRLGP8Aljhhk+oHBBHYiu/1ywktr+9slcxLeB5beT/e++B7hiT9GFVba0hst6w4jjkYFYxwAcY4+oGfzrslOUZM+DjCMoosnqT71NpGrWOlWv2O/ItyjuUmMZKSKWLD5gOCM4IPpmoaKyhLlNJw5kUr4xXusXlzYard3kN95IkiZSLe3WMhvkJ6sxXHHTcxJ6VPdQG5tZYQ20upAb0PY/nUx6881SP9qrlVNm4ycO24HHbKj/GnKbk7ijBQVifWr/TPFegCy1G31JCzrIRZjIZlPZ/u4znrj8CKsafHLd+GfE9vcY82bdcFQchN0Ywue+NmM96qWVs1tCyySCSR5Gkdgu0ZJycDsK0dLYJYeI5m4RbZVJ9xGx/kwraM3JtdCYw5JRkt7o8n6jNFA+6KK84/RQooooAKKKKACiiigAooooAKKkhgluJlhgieWVzhURck/gK7LSvh1KIPtviG7TTrVRlk3jdj3J4X9auEJTdoo5cRi6OHjepK35m34K1KbxPpL6dq9kbiC0xsuy2MEdBnruA7jtVGYaY3iMrp8lxPFFbkrJNKXQndglMnp2z37E06/wBf046d/YXh+CRdPjbyppuU80kZ2KTyQcjc3ocd+Mi2urez8RRW9xMvnPA8XmH7rMGQhQexA7V6Lg1Ts9WfDVakKld1ILli3ojoqKKZLIY4mdYnlI/gTGT+ZArjNCK4iupHHk3SwJjnEQZifqTj9KgOnzNy2q3pPsY1H6LUU2ryoQE0q/PTJ8nPrnoT6D86o3PiG+hWMDSZw0p2qZAEBO0E9TnHDHp0A9atRb2IbRsoosrd3nupZUX5i0uCQPQYAzUmvytoHgOWCf5L7V5SzRk8oDjI/BAqn3rn9P8AEd5Ya4k+rWMN5AhDQrG5QR7idr8jDHIKgnGCAeM102qyeE/FzxyX97caddKuxfPPlgD0ycofwNbqjNQbW7ChXorERdX4U7nl1Fdnqvw21C3g+1aVcx6lDjICcOR7dj+BrjXRkdkdSrKcFWGCD6GvPlCUPiR9zQxNHERvSlcSiiipOkKKKKACiiigAqzp1hcapfw2Nqm6aZtqjsPUn2HWq1d98PYIdN0vVPEtym4W6FI/U4GWx7ngVpThzyUTjxuJ+rUJVOvT1NQvp3gS2FhpsCXeqsgaadxwg9Wxz9FHX9a5nUby+1aI3Ul0bucjMRc4RPdV6Dj8fU0/fLK7z3Dbp5nMkrerHr+A6D2AqsP9GvAo/wBVcEkDsr9T+YyfqD6170KcYKyPzStXnWm5Td2ysrXllDgLDDA7rGVBLuFZgCdxwASTknByara5ATPZrHtA2yDawyrD5Tg1paipOnTleqLvH1X5v6VV1YhnspV6GRgD9UJ/pRKKUXYzc5SabI7HxBfWGITIJFHAhuicj/dfuPrn8K108V/L+80ufd/0zkRh+ZI/lWIVV1KsoYHqCMiofsNr2gQfTj+VcLpxfQ3jiJxVrmzd+LbgLiGyit8/x3MuSP8AgK9fzrGt5Lm/16C4nkeWRI3cPL8oI4G0L/Cpz9frT47eGI5jiRT6b2O4/gqk/hWlKEVLRClWnLdl9kl1IC7TYkLBljtpB8pjbsSOecZHYZ6Vas0nS1WO5Kl1yMht2V7ZOBk4qdVVVCqMKBgD0FLXcopHPKTk7sfp2o3Gk3ZbTZvKkXDPDz5Tg54ZenODyORWh4t0u18SaEPE2mQmO5hG27hHXjrn3X17isK0G6W6l/vzFR9FAX+YNdH4Svhaa39klINvqCmNlPTzACQfxXcPwWsK9JTgdmCxc8NWU4v+ux5tRWl4i0v+xtfvLAfcjkzH/unkfoaza8Fqzsz9OhNTipx2YUUUUiwooooABXoyKLP4W6fCODe3Clvf5y/8krzkV6Vq48vwZ4Zi9lf/AMhN/jXZg1eofOcRTaw0V5/ozFqvfRvJaSCP/WKN8f8AvLyP5Y/Gp33BDsALdgxwKrfbGiYfaoTAM4Em7cn59vxAr22fBomR0nhVxzHIoI+hFZNwCNItQxy1tOsbH6Ep/UfnV/TwVt2h/wCeMjIPpnI/QiqOrq0VrqAQZLItyg/2lIz/AOgr+dTLWJS3KVvqCSCUzbIAkjKu6QfMo71YaeFCoeaNS4yuWAz9K5ZNIuvs7GW0Lsto20EA/vGY/qBUc1lPHPHbT2xZ5pIY4pGIIVVHIHf61xWNeVHQXepLHfWtpDNGXeT96uclVAJ/Cr+hvb313c3cMglWMqisp4zg5/n+tcsujahPFsa3EMiJLmQuP3jsfzxjiup8MRSRRXnnIkbmZfkU5CjYuBmtaS94mSSRuUdxRUMkzPIbe3jee4xny4/4fQsTwo+tdTaSuzJJt2RFph3afE56yZk/76JP9astK9vtuY/9ZbusyfVSG/pj8azo57uyhSA2SzJbxASvbSmTZtABz8uM98ZrSBBweoP6iojKM1oy5RlB6ot/FC1je80/VocGO7h27h3xyD+TfpXC16HrcX9ofCy0lPzSadIIyfZWMf8ALBrzyvDxMeWoz9Fyar7TBx8tP6+QUUUVznrhRRRQAV6Vrh3eFfDDjp5YH/kL/wCtXmor0m8P2j4d6BcDnyZVU/8AfLp/PFduCf7w+a4ijfDxfn+hjUhAYEMAQRgg9DS1SuJ7qIb3eCBScKpVpWY/QEc+wzXtM+FJ9H0m2klvIZZLg7JFZFEzKAhXA6YzjaRz6Crd34Ztpo38m5uIWMbJlpDIuD1yG+nYiqOj30trfXE+owNDFJGiLKq5HBY5ZQSV+9/+qrviG6SbRkNvKkkE8yo7o2QVwTjI9SAPxrzKrqKrZN2PUpKm6V2kcdPq0VhO9vOGmWI7ftMK5jf3BP/ANenpa2UNyLxbWYTz8qTE+5sjPAI9PSrrQysrQuEaDGMkZZl/u46fjW7lpfBUUshJaKNXRj1+VvlP4gD86py5bGKpKV7HOvdxRf65ZYR6yxMo/MjFWtGurYyXYFzDlpFI/eDn5BWldR+bazRj+JDj2Pb9aRI4bqCOSSGN96BvmQHqM12Rp8rujjvdEkcct/Obe1kChcGWYYPlj0Hqx/TqewN6TTRawGKOOT7KuP3EGTJOx6l2/8Ar/U44rKOmWDdbK3/AO/Q/wAKP7Msh0tox/u8VlVozqO99DopV4U1bl1LV/Lb2duBqh3Aj93p1qCRj3A5Ye5wvtVTT2Q2oEbIcMxKIciPJJC884AOPwpBpdojM8SPC7dXjkYE/Xnn8asRxbMM5Dy42mTbgsO2aujR9mRWre06G/pS/a/BHiKzPOwtIo+sat/NTXmg6V6d4YIXRvEbN90QjP8A37b/AOtXmA6CvNxq98+y4ck3QkvNfkLRRRXCfTBRRRQAV6H4adtW+G2oWEY3z2TmSNR1OCJFH4kEV55W/wCDvEf/AAjmsedLua1mGydR1x2Ye4/xrahPkmmzzc0wzxOGlCO61RoKyuoZTlWGQfUUmxd4faNwGAcc4rd1jw+iWk2saHNDdafsaZog+DGMZOw9COvynGP0rmP7ThUAyxXMX+9Ax/VQRXvxmpK6PzWdOUHZlyql1ptrdxyK6FDIOXjYoT6Hjrg+tJ/a9h/z8gfVGH9KP7Wse0zN/uxO38hTdnuSrrYy49H1dZ41nvILq2DZkVgY2kHoSBx+Fb19q1vc2n9mCJ4J3MYERXK7N2ThhxjCn06dKz31qHcyRW1zKynBHl7McZ/ix61Snnvbm4SeMR2bIMZB8xmX0IIArmnCldPsbwrTSa7mxLcR/ZJZ0dXVVY5U5HHanWyGK1hjbqkaqfqBWCI5YrdbdEga2DFngVNgk+pye9SwuZb+CCE3tmrK5YecGU4AxjJb+VbKomY8pvUVUFteL9zUXP8A10hRv5AUbNRH/LzbH627D/2etLk2LdIzKilnYKqjJJ6AUyxtr+61K0tZLq3RJ5hGWWA5GQeeW9q6O6i8K+FLjdqV3NqN7Fhlt2AIU9QdoAH4tms51Yw3N6OHqV5ctNXfkQ3ROg/De6knBjutWf5UbhgGAABH+4uT7mvNq2fE3ia68TX4nmXyoYgRDCDkKPU+pNY1eHXqe0ndH6JleDeEocst3qwooorA9Q//2Q=="
}
