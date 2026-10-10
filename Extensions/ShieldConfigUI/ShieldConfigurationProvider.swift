import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationProvider: ShieldConfigurationDataSource {
    // 四个重载必须全部覆盖:类别锁定走 (application, in: category),
    // 白名单/访客模式的 .all(except:) 同样从类别重载进来——
    // 只实现单 App 重载会让 VIP 功能显示系统默认灰盾牌,品牌与引导全部丢失。
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(name: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application,
                                in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(name: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(name: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain,
                                in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(name: webDomain.domain)
    }

    private func makeConfiguration(name: String?) -> ShieldConfiguration {
        let state = AppGroupStore().load()
        let copy = ShieldCopy.make(isVIP: state.isVIP,
                                   appName: name,
                                   discreet: state.isDiscreetShieldEnabled)
        if state.isDiscreetShieldEnabled {
            // 无痕模式:全系统色、无品牌图标,看上去像一条普通的系统限制
            return ShieldConfiguration(
                backgroundBlurStyle: .systemMaterial,
                backgroundColor: UIColor.systemBackground.withAlphaComponent(0.6),
                icon: UIImage(systemName: "exclamationmark.circle")?
                    .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal),
                title: .init(text: copy.title, color: .label),
                subtitle: .init(text: copy.subtitle, color: .secondaryLabel),
                primaryButtonLabel: .init(text: copy.button, color: .label),
                primaryButtonBackgroundColor: .secondarySystemFill,
                secondaryButtonLabel: nil
            )
        }
        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: XLPalette.bg.withAlphaComponent(0.6),
            icon: UIImage(systemName: "lock.shield.fill")?
                .withTintColor(XLPalette.primary, renderingMode: .alwaysOriginal),
            title: .init(text: copy.title, color: XLPalette.ink),
            subtitle: .init(text: copy.subtitle, color: XLPalette.muted),
            primaryButtonLabel: .init(text: copy.button, color: XLPalette.onPrimary),
            primaryButtonBackgroundColor: XLPalette.primary,
            secondaryButtonLabel: nil
        )
    }
}
