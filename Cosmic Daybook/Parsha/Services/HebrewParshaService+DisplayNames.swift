// HebrewParshaService+DisplayNames.swift
// Human-readable names for the canonical parsha keys.

import Foundation

extension HebrewParshaService {

    // MARK: - Display Names

    private static let displayNames: [String: String] = [
        "bereishit": "Bereishit",
        "noach": "Noach",
        "lech-lecha": "Lech-Lecha",
        "vayera": "Vayera",
        "chayei-sarah": "Chayei Sarah",
        "toldot": "Toldot",
        "vayetzei": "Vayetzei",
        "vayishlach": "Vayishlach",
        "vayeshev": "Vayeshev",
        "miketz": "Miketz",
        "vayigash": "Vayigash",
        "vayechi": "Vayechi",
        "shemot": "Shemot",
        "vaera": "Vaera",
        "bo": "Bo",
        "beshalach": "Beshalach",
        "yitro": "Yitro",
        "mishpatim": "Mishpatim",
        "terumah": "Terumah",
        "tetzaveh": "Tetzaveh",
        "ki-tisa": "Ki Tisa",
        "vayakhel": "Vayakhel",
        "pekudei": "Pekudei",
        "vayakhel-pekudei": "Vayakhel\u{2013}Pekudei",
        "vayikra": "Vayikra",
        "tzav": "Tzav",
        "shemini": "Shemini",
        "tazria": "Tazria",
        "metzora": "Metzora",
        "tazria-metzora": "Tazria\u{2013}Metzora",
        "acharei-mot": "Acharei Mot",
        "kedoshim": "Kedoshim",
        "acharei-mot-kedoshim": "Acharei Mot\u{2013}Kedoshim",
        "emor": "Emor",
        "behar": "Behar",
        "bechukotai": "Bechukotai",
        "behar-bechukotai": "Behar\u{2013}Bechukotai",
        "bamidbar": "Bamidbar",
        "naso": "Naso",
        "behaalotecha": "Beha'alotecha",
        "shelach": "Shelach",
        "korach": "Korach",
        "chukat": "Chukat",
        "balak": "Balak",
        "chukat-balak": "Chukat\u{2013}Balak",
        "pinchas": "Pinchas",
        "matot": "Matot",
        "masei": "Masei",
        "matot-masei": "Matot\u{2013}Masei",
        "devarim": "Devarim",
        "vaetchanan": "Vaetchanan",
        "eikev": "Eikev",
        "reeh": "Re'eh",
        "shoftim": "Shoftim",
        "ki-teitzei": "Ki Teitzei",
        "ki-tavo": "Ki Tavo",
        "nitzavim": "Nitzavim",
        "vayelech": "Vayelech",
        "nitzavim-vayelech": "Nitzavim\u{2013}Vayelech",
        "haazinu": "Ha'azinu",
        "vzot-haberachah": "V'Zot HaBerachah"
    ]

    /// Returns a human-readable display name for a canonical parsha key. Doubled parshiot
    /// are formatted with an en-dash.
    static func displayName(forKey key: String) -> String {
        displayNames[key] ?? key.capitalized
    }
}
