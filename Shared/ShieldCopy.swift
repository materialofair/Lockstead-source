import Foundation

struct ShieldCopy {
    let title: String
    let subtitle: String
    let button: String

    static func make(isVIP: Bool, appName: String?, discreet: Bool = false) -> ShieldCopy {
        if discreet {
            // 无痕模式:不出现品牌名、不出现 PIN 提示,读起来像系统限制
            return ShieldCopy(
                title: String(localized: "shield.discreet.title"),
                subtitle: String(localized: "shield.discreet.subtitle"),
                button: String(localized: "shield.button.close")
            )
        }
        let name = appName ?? String(localized: "shield.thisapp")
        let subtitle = isVIP
            ? String(localized: "shield.subtitle.vip")     // 「在 Lockstead 中输入家长 PIN 解锁」
            : String(localized: "shield.subtitle.free")    // 同上 + VIP 高级隐私守护提示
        return ShieldCopy(
            title: String(localized: "shield.title \(name)"), // 「\(name) 已被 Lockstead 锁定」
            subtitle: subtitle,
            button: String(localized: "shield.button.close")
        )
    }
}
