import Cocoa


enum PasswordAction
{
  case save
  case change
  case useExisting
}


class AccountsPrefsController: NSViewController
{
  // Not a weak reference because there are no other references to it.
  @IBOutlet var addController: AddAccountController!
  @IBOutlet weak var accountsTable: NSTableView!
  @IBOutlet weak var refreshButton: NSButton!
  
  var authStatusObserver: NSObjectProtocol?
  
  override func viewDidLoad()
  {
    super.viewDidLoad()
    
    let notificationCenter = NotificationCenter.default
    
    AccountsManager.manager.readAccounts()
    authStatusObserver = notificationCenter.addObserver(
        forName: NSNotification.Name(rawValue:
            BasicAuthService.AuthenticationStatusChangedNotification),
        object: nil,
        queue: OperationQueue.main) {
      [weak self] (_) in
      self?.accountsTable.reloadData()
    }
    updateRefreshButton()
  }
  
  deinit
  {
    let center = NotificationCenter.default
    
    authStatusObserver.map { center.removeObserver($0) }
  }
  
  func updateRefreshButton()
  {
    refreshButton.isEnabled = accountsTable.selectedRow != -1
  }
  
  func showError(_ message: String)
  {
    let alert = NSAlert()
    
    alert.messageText = message
    alert.beginSheetModal(for: view.window!) { (_) in }
  }
  
  @IBAction func addAccount(_ sender: AnyObject)
  {
    addController.resetFields()
    view.window?.beginSheet(addController.window!,
                            completionHandler: addAccountDone)
  }
  
  func addAccountDone(response: NSApplication.ModalResponse)
  {
    guard response == NSApplication.ModalResponse.OK
    else { return }
    guard let url = self.addController.location
    else { return }
    
    self.addAccount(type: self.addController.accountType,
                    user: self.addController.userName,
                    password: self.addController.password,
                    location: url as URL)
    self.updateRefreshButton()
  }
  
  func addAccount(type: AccountType,
                  user: String,
                  password: String,
                  location: URL)
  {
    var passwordAction = PasswordAction.save
    
    if let oldPassword = XTKeychain.findPassword(url: location, account: user) {
      if oldPassword == password {
        passwordAction = .useExisting
      }
      else {
        let alert = NSAlert()
        
        alert.messageText =
            "There is already a password for that account in the keychain. " +
            "Do you want to change it, or use the existing password?"
        alert.addButton(withTitle: "Change")
        alert.addButton(withTitle: "Use existing")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: view.window!) {
          (response) in
          switch response {
            case NSApplication.ModalResponse.alertFirstButtonReturn:
              self.finishAddAccount(action: .change, type: type, user: user,
                                    password: password, location: location)
            case NSApplication.ModalResponse.alertSecondButtonReturn:
              self.finishAddAccount(action: .useExisting, type: type, user: user,
                                    password: "", location: location)
            default:
              break
          }
        }
        return
      }
    }
    finishAddAccount(action: passwordAction, type: type, user: user,
                     password: password, location: location)
  }
  
  func finishAddAccount(action: PasswordAction, type: AccountType,
                        user: String, password: String, location: URL)
  {
    switch action {
      case .save:
        do {
          try XTKeychain.savePassword(url: location, account: user,
                                      password: password)
        }
        catch _ as XTKeychain.Error {
          showError("The password could not be saved because the location " +
                    "field is incorrect.")
          return
        }
        catch _ as NSError {
          showError("The password could not be saved to the Keychain.")
          return
        }
      
      case .change:
        do {
          try XTKeychain.changePassword(url: location,
                                        account: user,
                                        password: password)
        }
        catch _ as NSError {
          showError("The password could not be saved to the Keychain.")
          return
        }
      
      default:
        break
    }
    
    AccountsManager.manager.add(Account(type: type,
                                  user: user,
                                  location: location))
    accountsTable.reloadData()
  }
  
  @IBAction func removeAccount(_ sender: AnyObject)
  {
    guard let window = view.window
    else { return }
    let alert = NSAlert()
    
    alert.messageText = "Are you sure you want to delete the selected account?"
    alert.addButton(withTitle: "Delete")
    alert.addButton(withTitle: "Cancel")
    // Cancel should be default for destructive actions
    alert.buttons[0].keyEquivalent = "D"
    alert.buttons[1].keyEquivalent = "\r"
    
    alert.beginSheetModal(for: window) {
      (response) in
      guard response == NSApplication.ModalResponse.alertFirstButtonReturn
      else { return }
      
      AccountsManager.manager.accounts.remove(at: self.accountsTable.selectedRow)
      self.accountsTable.reloadData()
      self.updateRefreshButton()
    }
  }
  
  @IBAction func refreshAccount(_ sender: Any)
  {
    let manager = AccountsManager.manager
    let selectedRow = accountsTable.selectedRow
    guard selectedRow >= 0 && selectedRow < manager.accounts.count
    else { return }
    let account = manager.accounts[selectedRow]
    
    switch account.type {
      
      case .teamCity:
        guard let api = Services.shared.teamCityAPI(account)
        else { break }
      
        api.attemptAuthentication()
      
      case .bitbucketServer:
        guard let api = Services.shared.bitbucketServerAPI(account)
        else { break }
      
        api.attemptAuthentication()
      
      default:
        break
    }
  }
}

extension AccountsPrefsController: PreferencesSaver
{
  func savePreferences()
  {
    AccountsManager.manager.saveAccounts()
  }
}


extension AccountsPrefsController: NSTableViewDelegate
{
  enum ColumnID
  {
    static let service = ¶"service"
    static let userName = ¶"userName"
    static let location = ¶"location"
    static let status = ¶"status"
  }
  
  func statusImage(forTeamCity api: TeamCityAPI?) -> NSImage?
  {
    guard let api = api
    else { return NSImage(named: NSImage.statusUnavailableName) }
    var imageName: NSImage.Name?
    
    switch api.authenticationStatus {
      case .unknown, .notStarted:
        imageName = NSImage.statusNoneName
      case .inProgress:
        // eventually have a spinner instead
        imageName = NSImage.statusPartiallyAvailableName
      case .done:
        break
      case .failed:
        imageName = NSImage.statusUnavailableName
    }
    if let imageName = imageName {
      return NSImage(named: imageName)
    }
    
    switch api.buildTypesStatus {
      case .unknown, .notStarted, .inProgress:
        imageName = NSImage.statusAvailableName
      case .done:
        imageName = NSImage.statusAvailableName
      case .failed:
        imageName = NSImage.statusPartiallyAvailableName
    }
    if let imageName = imageName {
      return NSImage(named: imageName)
    }
    return nil
  }
  
  func statusImage(forBitbucket api: BitbucketServerAPI?) -> NSImage?
  {
    guard let api = api
    else { return NSImage(named: NSImage.statusUnavailableName) }
    let imageName: NSImage.Name
    
    switch api.authenticationStatus {
      case .unknown, .notStarted:
        imageName = NSImage.statusNoneName
      case .inProgress:
        // eventually have a spinner instead
        imageName = NSImage.statusPartiallyAvailableName
      case .done:
        imageName = NSImage.statusAvailableName
      case .failed:
        imageName = NSImage.statusUnavailableName
    }
    return NSImage(named: imageName)
  }
  
  func tableView(_ tableView: NSTableView,
                 viewFor tableColumn: NSTableColumn?,
                 row: Int) -> NSView?
  {
    guard let tableColumn = tableColumn
    else { return nil }
    
    let view = tableView.makeView(withIdentifier: tableColumn.identifier,
                              owner: self)
               as! NSTableCellView
    let account = AccountsManager.manager.accounts[row]
    
    switch tableColumn.identifier {
      case ColumnID.service:
        view.textField?.stringValue = account.type.displayName
        view.imageView?.image = NSImage(named: account.type.imageName)
      case ColumnID.userName:
        view.textField?.stringValue = account.user
      case ColumnID.location:
        view.textField?.stringValue = account.location.absoluteString
      case ColumnID.status:
        view.imageView?.isHidden = true
        switch account.type {
          case .teamCity:
            let api = Services.shared.teamCityAPI(account)
            
            if let image = statusImage(forTeamCity: api) {
              view.imageView?.image = image
              view.imageView?.isHidden = false
            }
          case .bitbucketServer:
            let api = Services.shared.bitbucketServerAPI(account)
            
            if let image = statusImage(forBitbucket: api) {
              view.imageView?.image = image
              view.imageView?.isHidden = false
            }
          default:
            break
        }
      default:
        return nil
    }
    return view
  }
  
  func tableViewSelectionDidChange(_ notification: Notification)
  {
    updateRefreshButton()
  }
}


extension AccountsPrefsController: NSTableViewDataSource
{
  func numberOfRows(in tableView: NSTableView) -> Int
  {
    return AccountsManager.manager.accounts.count
  }
}
