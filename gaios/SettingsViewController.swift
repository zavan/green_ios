import Foundation
import UIKit
import NVActivityIndicatorView
import PromiseKit

class SettingsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {

    @IBOutlet weak var tableView: UITableView!

    var items = [SettingsItem]()
    var sections = [SettingsSections]()
    var data: Dictionary<SettingsSections, Any> = Dictionary()
    var username: String?
    var twoFactorConfig: TwoFactorConfig?
    var isResetActive: Bool {
        get {
            guard let twoFactorConfig = getGAService().getTwoFactorReset() else { return false }
            return twoFactorConfig.isResetActive
        }
    }
    var isDisputeActive: Bool {
        get {
            guard let twoFactorConfig = getGAService().getTwoFactorReset() else { return false }
            return twoFactorConfig.isDisputeActive
        }
    }
    var isWatchOnly: Bool { get { return getGAService().isWatchOnly } }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationItem.title = NSLocalizedString("id_settings", comment: "")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = 75
        tableView.rowHeight = 75
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let controller = self.tabBarController as? TabViewController else { return }
        controller.snackbar.isHidden = false
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let controller = self.tabBarController as? TabViewController else { return }
        controller.snackbar.isHidden = true
    }

    func reloadData() {
        let bgq = DispatchQueue.global(qos : .background)
        let isWatchOnly = getGAService().isWatchOnly
        Guarantee().compactMap(on: bgq) {
            if !isWatchOnly {
                self.username = try getGAService().getSession().getWatchOnlyUsername()
                let dataTwoFactorConfig = try getGAService().getSession().getTwoFactorConfig()
                self.twoFactorConfig = try JSONDecoder().decode(TwoFactorConfig.self, from: JSONSerialization.data(withJSONObject: dataTwoFactorConfig!, options: []))
            }
            return ()
        }.done {
            self.sections = self.getSections()
            self.items = self.getSettings()
            self.data = Dictionary(grouping: self.items) { (item) in
                return item.section
            }
            self.tableView.reloadData()
        }.catch { _ in }
    }

    func getSections() -> [SettingsSections] {
        if isWatchOnly {
            return [.network, .about]
        } else if isResetActive {
            return [.network, .twoFactor, .about]
        }
        return [.network, .account, .twoFactor, .security, .about]
    }

    func getSettings() -> [SettingsItem] {
        guard let settings = getGAService().getSettings() else { return [] }

        // Network settings
        let setupPin = SettingsItem(
            title: String(format: NSLocalizedString(AuthenticationTypeHandler.supportsBiometricAuthentication() ? "id_setup_pin_and_s" : "id_setup_pin", comment: ""), NSLocalizedString(AuthenticationTypeHandler.biometryType == .faceID ? "id_face_id" : "id_touch_id", comment: "")),
            subtitle: "",
            section: .network,
            type: .SetupPin)
        let watchOnly = SettingsItem(
            title: NSLocalizedString("id_watchonly_login", comment: ""),
            subtitle: String(format: NSLocalizedString((username == nil || username!.isEmpty) ? "id_set_up_watchonly_credentials" : "id_enabled_1s" , comment: ""), username ?? ""),
            section: .network,
            type: .WatchOnly)
        let logout = SettingsItem(
            title: String(format: NSLocalizedString("id_s_network", comment: ""), getNetwork()).localizedCapitalized,
            subtitle: NSLocalizedString("id_log_out", comment: ""),
            section: .network,
            type: .Logout)

        // Account settings
        let bitcoinDenomination = SettingsItem(
            title: NSLocalizedString("id_bitcoin_denomination", comment: ""),
            subtitle: settings.denomination.toString(),
            section: .account,
            type: .BitcoinDenomination)

        let referenceExchangeRate = SettingsItem(
            title: NSLocalizedString("id_reference_exchange_rate", comment: ""),
            subtitle: String(format: NSLocalizedString("id_s_from_s", comment: ""), settings.pricing["currency"]!, settings.pricing["exchange"]!),
            section: .account,
            type: .ReferenceExchangeRate)

        let defaultTransactionPriority = SettingsItem(
            title: NSLocalizedString("id_default_transaction_priority", comment: ""),
            subtitle: toString(settings.transactionPriority, detail: true),
            section: .account,
            type: .DefaultTransactionPriority)

        let defaultCustomFeeRate = SettingsItem(
            title: NSLocalizedString("id_default_custom_fee_rate", comment: ""),
            subtitle: String(format: "%.02f satoshi / vbyte", Float(settings.customFeeRate ?? 1000)/1000),
            section: .account,
            type: .DefaultCustomFeeRate)

        // Two Factor settings
        let setupTwoFactor = SettingsItem(
            title: NSLocalizedString("id_twofactor_authentication", comment: ""),
            subtitle: NSLocalizedString("id_set_up_twofactor_authentication", comment: ""),
            section: .twoFactor,
            type: .SetupTwoFactor)

        var thresholdValue = ""
        var locktimeRecoveryEnable = false
        if let twoFactorConfig = self.twoFactorConfig {
            let limits = twoFactorConfig.limits
            if limits.isFiat == true {
                thresholdValue = String(format: "%@ %@", limits.fiat, settings.getCurrency())
            } else {
                thresholdValue = String(format: "%@ %@", limits.get(TwoFactorConfigLimits.CodingKeys(rawValue: settings.denomination.rawValue)!)!, settings.denomination.toString())
            }
            if let notifications = settings.notifications {
                locktimeRecoveryEnable = notifications.emailOutgoing == true
            }
        }
        let thresholdTwoFactor = SettingsItem(
            title: NSLocalizedString("id_twofactor_threshold", comment: ""),
            subtitle: String(format: NSLocalizedString(thresholdValue == "" ? "id_set_twofactor_threshold" : "id_your_twofactor_threshold_is_s", comment: ""), thresholdValue),
            section: .twoFactor,
            type: .ThresholdTwoFactor)
        let locktimeRecovery = SettingsItem(
            title: NSLocalizedString("id_recovery_transaction_emails", comment: ""),
            subtitle: locktimeRecoveryEnable ? NSLocalizedString("id_enabled", comment: "") : NSLocalizedString("id_disabled", comment: ""),
            section: .twoFactor,
            type: .LockTimeRecovery)
        let locktimeRequest = SettingsItem(
            title: NSLocalizedString("id_request_recovery_transactions", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .LockTimeRequest)
        let resetTwoFactor = SettingsItem(
            title: NSLocalizedString("id_request_twofactor_reset", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .ResetTwoFactor)
        let disputeTwoFactor = SettingsItem(
            title: NSLocalizedString("id_dispute_twofactor_reset", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .DisputeTwoFactor)
        let cancelTwoFactor = SettingsItem(
            title: NSLocalizedString("id_cancel_twofactor_reset", comment: ""),
            subtitle: "",
            section: .twoFactor,
            type: .CancelTwoFactor)

        // Security settings
        let mnemonic = SettingsItem(
            title: NSLocalizedString("id_mnemonic", comment: ""),
            subtitle: NSLocalizedString("id_touch_to_display", comment: ""),
            section: .security,
            type: .Mnemonic)
        let autolock = SettingsItem(
            title: NSLocalizedString("id_auto_logout_timeout", comment: ""),
            subtitle: settings.autolock.toString(),
            section: .security,
            type: .Autolock)

        // About settings
        let versionSubtitle = String(format: NSLocalizedString("id_version_1s", comment: ""), Bundle.main.infoDictionary!["CFBundleShortVersionString"]! as! CVarArg)
        let version = SettingsItem(
            title: NSLocalizedString("id_version", comment: ""),
            subtitle: versionSubtitle,
            section: .about,
            type: .Version)
        let termOfUse = SettingsItem(
            title: NSLocalizedString("id_terms_of_use", comment: ""),
            subtitle: "",
            section: .about,
            type: .TermsOfUse)
        let privacyPolicy = SettingsItem(
            title: NSLocalizedString("id_privacy_policy", comment: ""),
            subtitle: "",
            section: .about,
            type: .PrivacyPolicy)

        var menu = [SettingsItem]()
        if !isWatchOnly && !isResetActive {
            menu.append(contentsOf: [setupPin, watchOnly])
        }
        menu.append(logout)
        if !isWatchOnly && !isResetActive {
            menu.append(contentsOf: [bitcoinDenomination, referenceExchangeRate, defaultTransactionPriority, defaultCustomFeeRate, setupTwoFactor])
            if twoFactorConfig?.anyEnabled ?? false {
                menu.append(contentsOf: [thresholdTwoFactor])
                if twoFactorConfig?.enableMethods.contains("email") ?? false {
                    menu.append(contentsOf: [locktimeRecovery, locktimeRequest])
                }
                menu.append(contentsOf: [resetTwoFactor])
            }
        }
        if !isWatchOnly && isResetActive {
            if !isDisputeActive {
                menu.append(disputeTwoFactor)
            }
            menu.append(cancelTwoFactor)
        }
        if !isWatchOnly && !isResetActive {
            menu.append(contentsOf: [mnemonic, autolock])
        }
        menu.append(contentsOf: [version, termOfUse, privacyPolicy])
        return menu
    }

    func toString(_ tp: TransactionPriority, detail: Bool) -> String {
        switch tp {
        case .Low:
            return NSLocalizedString(detail ? "id_confirmation_in_24_blocks_4" : "id_slow", comment: "")
        case .Medium:
            return NSLocalizedString(detail ? "id_confirmation_in_12_blocks_2" : "id_medium", comment: "")
        case .High:
            return NSLocalizedString(detail ? "id_confirmation_in_3_blocks_30" : "id_fast", comment: "")
        default:
            return ""
        }
    }

    func toString(_ section: SettingsSections) -> String {
        switch section {
        case .about:
            return NSLocalizedString("id_about", comment: "")
        case .account:
            return NSLocalizedString("id_account", comment: "")
        case .network:
            return NSLocalizedString("id_network", comment: "")
        case .twoFactor:
            return NSLocalizedString("id_twofactor", comment: "")
        case .security:
            return NSLocalizedString("id_security", comment: "")
        case .advanced:
            return NSLocalizedString("id_advanced", comment: "")
        }
    }

    func logout() {
        let bgq = DispatchQueue.global(qos: .background)
        Guarantee().map() {
            self.startAnimating()
        }.map(on: bgq) {
            try getSession().disconnect()
        }.ensure {
            self.stopAnimating()
        }.done {
            getGAService().reset()
            getAppDelegate().instantiateViewControllerAsRoot(identifier: "InitialViewController")
        }.catch { _ in
            print("disconnection error never happens")
        }
    }

    func getHeaderImage(from sectionIndex: Int) -> UIImage {
        let section : SettingsSections = sections[sectionIndex]
        switch section {
        case .about:
            return UIImage(named: "about")!
        case .account:
            return UIImage(named: "account")!
        case .advanced:
            return UIImage(named: "advanced")!
        case .network:
            return UIImage(named: "network")!
        case .security:
            return UIImage(named: "security")!
        case .twoFactor:
            return UIImage(named: "twofactor")!
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = sections[section]
        let itemsInSection = data[section] as! [SettingsItem]
        return itemsInSection.count
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        view.backgroundColor = UIColor.customTitaniumDark()
        view.tintColor = UIColor.customMatrixGreen()
        guard let header = view as? UITableViewCell else { return }
        header.textLabel?.textColor = UIColor.customMatrixGreen()
        header.textLabel?.font = UIFont.systemFont(ofSize: 16.00, weight: .light)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = UITableViewCell()
        header.textLabel?.text = toString(sections[section])
        header.imageView?.image = getHeaderImage(from: section)
        return header
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 43
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell =
            tableView.dequeueReusableCell(withIdentifier: "SettingsCell",
                                          for: indexPath as IndexPath)
        let section = sections[indexPath.section]
        let itemsInSection = data[section] as! [SettingsItem]
        let item: SettingsItem = itemsInSection[indexPath.row]
        cell.textLabel!.text = item.title
        cell.detailTextLabel?.text = item.subtitle
        cell.detailTextLabel?.numberOfLines = 2
        cell.detailTextLabel?.textColor = item.type == .Logout ? UIColor.errorRed() : UIColor.lightGray
        cell.selectionStyle = .none
        cell.accessoryType = item.type == .Version ? .none : .disclosureIndicator
        cell.setNeedsLayout()
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = sections[indexPath.section]
        let itemsInSection = data[section] as! [SettingsItem]
        let item: SettingsItem = itemsInSection[indexPath.row]
        guard let settings = getGAService().getSettings() else { return }

        switch item.type {
        case .BitcoinDenomination:
            let list = [DenominationType.BTC.toString(), DenominationType.MilliBTC.toString(),  DenominationType.MicroBTC.toString(), DenominationType.Bits.toString()]
            let selected = settings.denomination.toString()
            let popup = PopupList(self, title: item.title, list: list, selected: selected)
            resolvePopup(popup: popup, setting: { (_ value: Any) throws -> TwoFactorCall in
                settings.denomination = DenominationType.fromString(value as! String)
                return try getGAService().getSession().changeSettings(details: try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings), options: .allowFragments) as! [String : Any])
            }, completing: { self.reloadData() })
            break
        case .SetupPin:
            self.performSegue(withIdentifier: "screenLock", sender: nil)
            break
        case .Logout:
            self.logout()
            break
        case .WatchOnly:
            let alert = UIAlertController(title: NSLocalizedString("id_set_up_watchonly", comment: ""), message: NSLocalizedString("id_allows_you_to_quickly_check", comment: ""), preferredStyle: .alert)
            alert.addTextField { (textField) in textField.placeholder = NSLocalizedString("id_username", comment: "") }
            alert.addTextField { (textField) in textField.placeholder = NSLocalizedString("id_password", comment: "") }
            alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
            alert.addAction(UIAlertAction(title: NSLocalizedString("id_save", comment: ""), style: .default) { _ in
                let username = alert.textFields![0].text!
                let password = alert.textFields![1].text!
                self.setWatchOnly(username: username, password: password)
            })
            self.present(alert, animated: true, completion: nil)
            break
        case .ReferenceExchangeRate:
            self.performSegue(withIdentifier: "currency", sender: nil)
            break
        case .DefaultTransactionPriority:
            let list = [toString(TransactionPriority.High, detail: false),
                        toString(TransactionPriority.Medium, detail: false),
                        toString(TransactionPriority.Low, detail: false)]
            let selected = toString(settings.transactionPriority, detail: false)
            let popup = PopupList(self, title: item.title, list: list, selected: selected)
            resolvePopup(popup: popup, setting: { (_ value: Any) throws -> TwoFactorCall in
                guard let string = value as? String else { throw GaError.GenericError }
                if string == self.toString(.Low, detail: false) { settings.transactionPriority = .Low}
                else if string == self.toString(.Medium, detail: false) { settings.transactionPriority = .Medium}
                else if string == self.toString(.High, detail: false) { settings.transactionPriority = .High}
                return try getGAService().getSession().changeSettings(details: try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings), options: .allowFragments) as! [String : Any])
            }, completing: { self.reloadData() })
            break
        case .DefaultCustomFeeRate:
            let hint = String(format: "%.02f", Float(settings.customFeeRate ?? 1000) / 1000)
            let popup = PopupEditable(self, title: item.title, hint: hint, text: hint, keyboardType: .numberPad)
            resolvePopup(popup: popup, setting: { (_ value: Any) throws -> TwoFactorCall in
                let amount = (value as! String).replacingOccurrences(of: ",", with: ".")
                guard let feeRate = Double(amount) else { throw GaError.GenericError }
                settings.customFeeRate = UInt64(feeRate * 1000)
                return try getGAService().getSession().changeSettings(details: try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings), options: .allowFragments) as! [String : Any])
            }, completing: { self.reloadData() })
            break
        case .SetupTwoFactor:
            self.performSegue(withIdentifier: "setupTwoFactor", sender: nil)
            break
        case .ThresholdTwoFactor:
            self.performSegue(withIdentifier: "twoFactorLimit", sender: nil)
            break
        case .ResetTwoFactor:
            let hint = "jane@example.com"
            let popup = PopupEditable(self, title: item.title, hint: hint, text: nil, keyboardType: .emailAddress)
            resolvePopup(popup: popup, setting: { (_ value: Any) throws -> TwoFactorCall in
                guard let email = value as? String else { throw GaError.GenericError }
                return try getGAService().getSession().resetTwoFactor(email: email, isDispute: false)
            }, completing: { self.logout() })
            break
        case .DisputeTwoFactor:
            let hint = "jane@example.com"
            let popup = PopupEditable(self, title: item.title, hint: hint, text: nil, keyboardType: .emailAddress)
            resolvePopup(popup: popup, setting: { (_ value: Any) throws -> TwoFactorCall in
                guard let email = value as? String else { throw GaError.GenericError }
                return try getGAService().getSession().resetTwoFactor(email: email, isDispute: true)
            }, completing: { self.logout() })
            break
        case .CancelTwoFactor:
            setCancelTwoFactor()
            break
        case .LockTimeRecovery:
            var enabled = false
            if let notifications = settings.notifications {
                enabled = notifications.emailOutgoing == true
            }
            let alert = UIAlertController(title: NSLocalizedString("id_recovery_transaction_emails", comment: ""), message: "", preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: NSLocalizedString("id_enable", comment: ""), style: enabled ? .destructive : .default) { _ in
                self.setRecoveryEmail(true)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("id_disable", comment: ""), style: !enabled ? .destructive : .default) { _ in
                self.setRecoveryEmail(false)
            })
            alert.addAction(UIAlertAction(title: NSLocalizedString("id_cancel", comment: ""), style: .cancel) { _ in })
            self.present(alert, animated: true, completion: nil)
            break
        case .LockTimeRequest:
            setLockTimeRequest()
        case .Mnemonic:
            self.performSegue(withIdentifier: "recovery", sender: nil)
            break
        case .Autolock:
            let list = [AutoLockType.minute.toString(), AutoLockType.twoMinutes.toString(), AutoLockType.fiveMinutes.toString(), AutoLockType.tenMinutes.toString()]
            let selected = settings.autolock.toString()
            let popup = PopupList(self, title: item.title, list: list, selected: selected)
            resolvePopup(popup: popup, setting: { (_ value: Any) throws -> TwoFactorCall in
                settings.autolock = AutoLockType.fromString(value as! String)
                return try getGAService().getSession().changeSettings(details: try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings), options: .allowFragments) as! [String : Any])
            }, completing: { self.reloadData() })
            break
        case .TermsOfUse:
            UIApplication.shared.open(URL(string: "https://greenaddress.it/tos.html")!)
            break
        case .PrivacyPolicy:
            UIApplication.shared.open(URL(string: "https://greenaddress.it/privacy.html")!)
            break
        case .Version:
            break
        }
    }

    func resolvePopup(popup: PopupPromise, setting: @escaping (_ value: Any) throws -> TwoFactorCall, completing: @escaping () -> ()) {
        let bgq = DispatchQueue.global(qos: .background)
        popup.show().get {_ in
            self.startAnimating()
        }.compactMap(on: bgq) { newValue in
            try setting(newValue)
        }.then(on: bgq) { call in
            call.resolve(self)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            completing()
        }.catch { error in
            self.showAlert(error)
        }
    }

    func showAlert(_ error: Error) {
        let text: String
        if error is TwoFactorCallError {
            switch error as! TwoFactorCallError {
            case .failure(let localizedDescription), .cancel(let localizedDescription):
                text = localizedDescription
            }
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: text)
        }
    }

    func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("id_continue", comment: ""), style: .cancel) { _ in })
        self.present(alert, animated: true, completion: nil)
    }

    func setWatchOnly(username: String, password: String) {
        if username.isEmpty {
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_enter_a_valid_username", comment: ""))
            return
        } else if password.isEmpty {
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_the_password_cant_be_empty", comment: ""))
            return
        }
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.compactMap(on: bgq) {
            try getGAService().getSession().setWatchOnly(username: username, password: password)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.reloadData()
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_username_not_available", comment: ""))
        }
    }

    func setCancelTwoFactor() {
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.compactMap(on: bgq) {
            try getGAService().getSession().cancelTwoFactorReset()
        }.then(on: bgq) { call in
            call.resolve(self)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.logout()
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_cancel_twofactor_reset", comment: ""))
        }
    }

    func setLockTimeRequest() {
        let bgq = DispatchQueue.global(qos: .background)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.compactMap(on: bgq) {
            return try getSession().sendNlocktimes()
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.showAlert(title: NSLocalizedString("id_request_sent", comment: ""), message: NSLocalizedString("id_recovery_transaction_request", comment: ""))
        }.catch {_ in
            self.showAlert(title: NSLocalizedString("id_error", comment: ""), message: NSLocalizedString("id_request_failure", comment: ""))
        }
    }

    func setRecoveryEmail(_ value: Bool) {
        guard let settings = getGAService().getSettings() else { return }
        let bgq = DispatchQueue.global(qos: .background)
        let data = ["email_incoming": value, "email_outgoing": value]
        let json = try! JSONSerialization.data(withJSONObject: data, options: [])
        settings.notifications = try! JSONDecoder().decode(SettingsNotifications.self, from: json)
        firstly {
            self.startAnimating()
            return Guarantee()
        }.compactMap(on: bgq) {
            try getGAService().getSession().changeSettings(details: try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings), options: .allowFragments) as! [String : Any])
        }.then(on: bgq) { call in
            call.resolve(self)
        }.ensure {
            self.stopAnimating()
        }.done { _ in
            self.reloadData()
        }.catch { error in
            self.showAlert(error)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let controller = segue.destination as? EnableTwoFactorViewController {
            controller.isHiddenWalletButton = true
        }
    }
}
