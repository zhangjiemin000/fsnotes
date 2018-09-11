//
//  ViewController.swift
//  FSNotes iOS
//
//  Created by Oleksandr Glushchenko on 1/29/18.
//  Copyright © 2018 Oleksandr Glushchenko. All rights reserved.
//

import UIKit
import NightNight
import Solar

class ViewController: UIViewController, UISearchBarDelegate, UIGestureRecognizerDelegate {

    @IBOutlet weak var currentFolder: UILabel!
    @IBOutlet weak var folderCapacity: UILabel!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var search: UISearchBar!
    @IBOutlet weak var searchWidth: NSLayoutConstraint!
    @IBOutlet var notesTable: NotesTableView!
    @IBOutlet weak var sidebarTableView: SidebarTableView!
    @IBOutlet weak var sidebarWidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var notesWidthConstraint: NSLayoutConstraint!
    
    private let indicator = UIActivityIndicatorView(activityIndicatorStyle: UIActivityIndicatorViewStyle.whiteLarge)
    
    let storage = Storage.sharedInstance()
    public var cloudDriveManager: CloudDriveManager?
    
    public var shouldReloadNotes = false
    private var maxSidebarWidth = CGFloat(0)
    
    override func viewDidLoad() {
        UIApplication.shared.statusBarStyle = MixedStatusBarStyle(normal: .default, night: .lightContent).unfold()

        view.mixedBackgroundColor = MixedColor(normal: 0xfafafa, night: 0x47444e)
        
        notesTable.mixedBackgroundColor = MixedColor(normal: 0xffffff, night: 0x2e2c32)
        sidebarTableView.mixedBackgroundColor = MixedColor(normal: 0x5291ca, night: 0x313636)
        
//        let searchBarTextField = search.value(forKey: "searchField") as? UITextField
  //      searchBarTextField?.mixedTextColor = MixedColor(normal: 0x000000, night: 0xfafafa)
        
        loadPlusButton()
        initSettingsButton()
        
       // search.delegate = self
       // search.autocapitalizationType = .none
       // search.sizeToFit()
        
        notesTable.viewDelegate = self
        
        notesTable.dataSource = notesTable
        notesTable.delegate = notesTable
        
        sidebarTableView.dataSource = sidebarTableView
        sidebarTableView.delegate = sidebarTableView
        sidebarTableView.viewController = self
        
        UserDefaultsManagement.fontSize = 17
                
        if storage.noteList.count == 0 {
            DispatchQueue.global().async {
                self.storage.initiateCloudDriveSync()
            }
            
            DispatchQueue.global().async {
                self.storage.loadDocuments()
                DispatchQueue.main.async {
                    self.updateTable() {}
                    self.indicator.stopAnimating()
                    self.sidebarTableView.sidebar = Sidebar()
                    self.maxSidebarWidth = self.calculateLabelMaxWidth()
                    self.sidebarTableView.reloadData()
                    self.cloudDriveManager = CloudDriveManager(delegate: self, storage: self.storage)

                    if let note = Storage.sharedInstance().noteList.first {
                        let evc = self.getEVC()
                        evc?.fill(note: note)
                    }
                }
            }
        }
        
        self.sidebarTableView.sidebar = Sidebar()
        self.sidebarTableView.reloadData()

        guard let pageController = self.parent as? PageViewController else {
            return
        }
        
        pageController.disableSwipe()

        keyValueWatcher()
        
        NotificationCenter.default.addObserver(self, selector: #selector(preferredContentSizeChanged), name: NSNotification.Name.UIContentSizeCategoryDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(rotated), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(didChangeScreenBrightness), name: NSNotification.Name.UIScreenBrightnessDidChange, object: nil)
        
        NotificationCenter.default.addObserver(self, selector:#selector(viewWillAppear(_:)), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.keyboardWillShow), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.keyboardWillHide), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        let swipe = UIPanGestureRecognizer(target: self, action: #selector(handleSidebarSwipe))
        swipe.minimumNumberOfTouches = 1
        swipe.delegate = self
        
        view.addGestureRecognizer(swipe)
        super.viewDidLoad()
        
        self.indicator.color = NightNight.theme == .night ? UIColor.white : UIColor.black
        self.indicator.frame = CGRect(x: 0.0, y: 0.0, width: 40.0, height: 40.0)
        self.indicator.center = self.view.center
        self.self.view.addSubview(indicator)
        self.indicator.bringSubview(toFront: self.view)
        self.indicator.startAnimating()
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let recognizer = gestureRecognizer as? UIPanGestureRecognizer {
            if recognizer.translation(in: self.view).x > 0 || sidebarTableView.frame.width != 0 {
                return true
            }
        }
        return false
    }

    override func viewWillAppear(_ animated: Bool) {
        let width = UserDefaultsManagement.sidebarSize
        sidebarWidthConstraint.constant = width
        notesWidthConstraint.constant = view.frame.width - width
    }

    override var preferredStatusBarStyle : UIStatusBarStyle {
        return MixedStatusBarStyle(normal: .default, night: .lightContent).unfold()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    var filterQueue = OperationQueue.init()
    var filteredNoteList: [Note]?
    
    func keyValueWatcher() {
        let keyStore = NSUbiquitousKeyValueStore()
        
        NotificationCenter.default.addObserver(self,
           selector: #selector(ubiquitousKeyValueStoreDidChange),
           name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
           object: keyStore)
        
        keyStore.synchronize()
    }
    
    @objc func ubiquitousKeyValueStoreDidChange(notification: NSNotification) {
        if let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            let keyStore = NSUbiquitousKeyValueStore()
            for key in keys {
                if let isPinned = keyStore.object(forKey: key) as? Bool, let note = storage.getBy(name: key) {
                    note.isPinned = isPinned
                }
            }
            
            DispatchQueue.main.async {
                self.updateTable() {}
            }
        }
    }
            
    private func getEVC() -> EditorViewController? {
        if let pageController = UIApplication.shared.windows[0].rootViewController as? PageViewController,
            let viewController = pageController.orderedViewControllers[1] as? UINavigationController,
            let evc = viewController.viewControllers[0] as? EditorViewController {
            return evc
        }
        
        return nil
    }
        
    public func updateTable(search: Bool = false, completion: @escaping () -> Void) {
        let filter = ""//self.search.text!

        var type: SidebarItemType? = nil
        var terms = filter.split(separator: " ")

        if let sidebarItem = getSidebarItem() {
            type = sidebarItem.type
        }

        if let type = type, type == .Todo {
            terms.append("- [ ]")
        }

        let filteredNoteList =
            storage.noteList.filter() {
                return (
                    !$0.name.isEmpty
                    && (
                        filter.isEmpty && type != .Todo || type == .Todo && (
                            self.isMatched(note: $0, terms: ["- [ ]"])
                                || self.isMatched(note: $0, terms: ["- [x]"])
                            )
                            || self.isMatched(note: $0, terms: terms)
                    ) && (
                        isFitInSidebar(note: $0)
                    )
                )
        }

        DispatchQueue.main.async {
            self.folderCapacity.text = String(filteredNoteList.count)
        }
        
        if !filteredNoteList.isEmpty {
            notesTable.notes = storage.sortNotes(noteList: filteredNoteList, filter: "")
        } else {
            notesTable.notes.removeAll()
        }
        
        DispatchQueue.main.async {
            self.notesTable.reloadData()
            
            completion()
        }
    }
    
    public func isFitInSidebar(note: Note) -> Bool {
        var type: SidebarItemType? = nil
        var project: Project? = nil
        var sidebarName = ""
        
        if let sidebarItem = getSidebarItem() {
            sidebarName = sidebarItem.name
            type = sidebarItem.type
            project = sidebarItem.project
        }
        
        if type == .Trash && note.isTrash()
            || type == .All && !note.isTrash() && !note.project!.isArchive
            || type == .Tag && note.tagNames.contains(sidebarName)
            || [.Category, .Label].contains(type) && project != nil && note.project == project
            || type == nil && project == nil && !note.isTrash()
            || project != nil && project!.isRoot && note.project?.parent == project
            || type == .Archive && note.project != nil && note.project!.isArchive
            || type == .Todo {
            
            return true
        }
        
        return false
    }

    public func insertRow(note: Note) {
        let i = self.getInsertPosition()

        DispatchQueue.main.async {
            if self.isFitInSidebar(note: note), !self.notesTable.notes.contains(note) {

                self.notesTable.notes.insert(note, at: i)
                self.notesTable.beginUpdates()
                self.notesTable.insertRows(at: [IndexPath(row: i, section: 0)], with: .automatic)
                self.notesTable.reloadRows(at: [IndexPath(row: i, section: 0)], with: .automatic)
                self.notesTable.endUpdates()
            }
        }
    }

    private func isMatched(note: Note, terms: [Substring]) -> Bool {
        for term in terms {
            if note.name.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil || note.content.string.range(of: term, options: .caseInsensitive, range: nil, locale: nil) != nil {
                continue
            }

            return false
        }

        return true
    }
    
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        updateTable(completion: {})
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        guard let name = searchBar.text, name.count > 0 else {
            searchBar.endEditing(true)
            return
        }
        guard let project = storage.getProjects().first else { return }
        
        search.text = ""
        
        let note = Note(name: name, project: project)
        note.save()
        
        self.updateTable() {}
        
        guard let pageController = UIApplication.shared.windows[0].rootViewController as? PageViewController, let viewController = pageController.orderedViewControllers[1] as? UINavigationController, let evc = viewController.viewControllers[0] as? EditorViewController else {
            return
        }
    
        evc.note = note
        pageController.switchToEditor()
        evc.fill(note: note)
    }
    
    func reloadView(note: Note?) {
        DispatchQueue.main.async {
            self.updateTable() {}
        }
    }
    
    func refillEditArea(cursor: Int?, previewOnly: Bool) {
        DispatchQueue.main.async {
            guard let pageController = UIApplication.shared.windows[0].rootViewController as? PageViewController, let viewController = pageController.orderedViewControllers[1] as? UINavigationController, let evc = viewController.viewControllers[0] as? EditorViewController else {
                return
            }
        
            if let note = evc.note {
                evc.fill(note: note)
            }
        }
    }
    
    private var addButton: UIButton?
    
    func loadPlusButton() {
        if let button = getButton() {
            let width = self.view.frame.width
            let height = self.view.frame.height
            
            button.frame = CGRect(origin: CGPoint(x: CGFloat(width - 80), y: CGFloat(height - 80)), size: CGSize(width: 48, height: 48))
            return
        }
        
        let button = UIButton(frame: CGRect(origin: CGPoint(x: self.view.frame.width - 80, y: self.view.frame.height - 80), size: CGSize(width: 48, height: 48)))
        let image = UIImage(named: "plus.png")
        button.setImage(image, for: UIControlState.normal)
        button.tag = 1
        button.tintColor = UIColor(red:0.49, green:0.92, blue:0.63, alpha:1.0)
        button.addTarget(self, action: #selector(self.newButtonAction), for: .touchDown)
        self.view.addSubview(button)
    }
    
    private func getButton() -> UIButton? {
        for sub in self.view.subviews {
            
            if sub.tag == 1 {
                return sub as? UIButton
            }
        }
        
        return nil
    }
    
    func initSettingsButton() {
        let settingsIcon = UIImage(named: "settings.png")
        settingsButton.setImage(settingsIcon, for: UIControlState.normal)
        settingsButton.tintColor = UIColor.black
        settingsButton.addTarget(self, action: #selector(self.openSettings), for: .touchDown)
    }
    
    @objc func newButtonAction() {
        createNote(content: nil)
    }
    
    func createNote(content: String? = nil) {
        var currentProject: Project
        var tag: String?
        
        if let project = storage.getProjects().first {
            currentProject = project
        } else {
            return
        }
        
        if let item = getSidebarItem() {
            if item.type == .Tag {
                tag = item.name
            }
            
            if let project = item.project, !project.isTrash {
                currentProject = project
            }
        }
        
        let note = Note(name: "", project: currentProject)
        
        if let tag = tag {
            note.tagNames.append(tag)
        }
        
        if let content = content {
            note.content = NSMutableAttributedString(string: content)
        }

        note.save(to: note.url, for: .forCreating, completionHandler: nil)
        
        guard let pageController = UIApplication.shared.windows[0].rootViewController as? PageViewController, let viewController = pageController.orderedViewControllers[1] as? UINavigationController, let evc = viewController.viewControllers[0] as? EditorViewController else {
            return
        }
        
        evc.note = note
        pageController.switchToEditor()
        evc.fill(note: note)
        evc.editArea.becomeFirstResponder()
        
        self.shouldReloadNotes = true
    }
    
    @objc func openSettings() {
        let storyBoard: UIStoryboard = UIStoryboard(name: "Main", bundle:nil)
        let sourceSelectorTableViewController = storyBoard.instantiateViewController(withIdentifier: "settingsViewController") as! SettingsViewController
        let navigationController = UINavigationController(rootViewController: sourceSelectorTableViewController)
                
        self.present(navigationController, animated: true, completion: nil)
    }
    
    @objc func preferredContentSizeChanged() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    @objc func rotated() {
        viewWillAppear(false)
        loadPlusButton()
        
        guard
            let pageController = UIApplication.shared.windows[0].rootViewController as? PageViewController,
            let viewController = pageController.orderedViewControllers[1] as? UINavigationController,
            let evc = viewController.viewControllers[0] as? EditorViewController else { return }
        
        evc.reloadPreview()
    }
    
    @objc func didChangeScreenBrightness() {
        guard UserDefaultsManagement.nightModeType == .brightness else {
            return
        }
        
        guard
            let pageController = UIApplication.shared.windows[0].rootViewController as? PageViewController,
            let viewController = pageController.orderedViewControllers[1] as? UINavigationController,
            let evc = viewController.viewControllers[0] as? EditorViewController,
            let vc = pageController.orderedViewControllers[0] as? ViewController else {
            return
        }
        
        let brightness = Float(UIScreen.screens[0].brightness)

        if (UserDefaultsManagement.maxNightModeBrightnessLevel < brightness && NightNight.theme == .night) {
            NightNight.theme = .normal
            UIApplication.shared.statusBarStyle = .default
            
            UserDefaultsManagement.codeTheme = "atom-one-light"
            NotesTextProcessor.hl = nil
            evc.refill()
            
            vc.sidebarTableView.sidebar = Sidebar()
            vc.sidebarTableView.reloadData()
            vc.notesTable.reloadData()
            
            return
        }
        
        if (UserDefaultsManagement.maxNightModeBrightnessLevel > brightness && NightNight.theme == .normal) {
            NightNight.theme = .night
            UIApplication.shared.statusBarStyle = .lightContent
            
            UserDefaultsManagement.codeTheme = "monokai-sublime"
            NotesTextProcessor.hl = nil
            evc.refill()
            
            vc.sidebarTableView.sidebar = Sidebar()
            vc.sidebarTableView.reloadData()
            vc.notesTable.reloadData()
        }
    }
    
    public func getSidebarItem() -> SidebarItem? {
        guard
            let indexPath = sidebarTableView.indexPathForSelectedRow,
            let sidebar = sidebarTableView.sidebar,
            let item = sidebar.getByIndexPath(path: indexPath) else { return nil }
        
        return item
    }
    
    var sidebarWidth: CGFloat = 0
    var width: CGFloat = 0

    @objc func handleSidebarSwipe(_ swipe: UIPanGestureRecognizer) {
        guard let pageViewController = UIApplication.shared.windows[0].rootViewController as? PageViewController,
            let vc = pageViewController.orderedViewControllers[0] as? ViewController else { return }
        
        let windowWidth = self.view.frame.width
        let translation = swipe.translation(in: vc.notesTable)
        
        if swipe.state == .began {
            self.width = vc.notesTable.frame.size.width
            self.sidebarWidth = vc.sidebarTableView.frame.size.width
            return
        }

        let sidebarWidth = self.sidebarWidth + translation.x
        
        if swipe.state == .changed {
            if sidebarWidth > self.maxSidebarWidth {
                vc.sidebarTableView.frame.size.width = self.maxSidebarWidth
                vc.notesTable.frame.size.width = windowWidth - self.maxSidebarWidth
                vc.notesTable.frame.origin.x = self.maxSidebarWidth
            } else if sidebarWidth < 0 {
                vc.sidebarTableView.frame.size.width = 0
                vc.notesTable.frame.origin.x = 0
                vc.notesTable.frame.size.width = windowWidth
            } else {
                vc.sidebarTableView.frame.size.width = sidebarWidth
                vc.notesTable.frame.size.width = windowWidth - sidebarWidth
                vc.notesTable.frame.origin.x = sidebarWidth
            }
        }
        
        if swipe.state == .ended {
            UIView.animate(withDuration: 0.1, animations: {
                if translation.x > 0 {
                    vc.sidebarTableView.frame.size.width = self.maxSidebarWidth
                    vc.notesTable.frame.size.width = windowWidth - self.maxSidebarWidth
                    vc.notesTable.frame.origin.x = self.maxSidebarWidth

                    UserDefaultsManagement.sidebarSize = self.maxSidebarWidth
                    self.viewWillAppear(false)
                }

                if translation.x < 0 {
                    vc.sidebarTableView.frame.size.width = 0
                    vc.notesTable.frame.origin.x = 0
                    vc.notesTable.frame.size.width = windowWidth
                    UserDefaultsManagement.sidebarSize = 0

                }
            })

        }
    }
    
    @objc func keyboardWillShow(notification: NSNotification) {
        if let keyboardSize = (notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            self.view.frame.size.height = UIScreen.main.bounds.height
            self.view.frame.size.height -= keyboardSize.height
            loadPlusButton()
        }
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        self.view.frame.size.height = UIScreen.main.bounds.height
        loadPlusButton()
    }
    
    public func getInsertPosition() -> Int {
        var i = 0
        
        for note in notesTable.notes {
            if note.isPinned {
                i += 1
            }
        }
        
        return i
    }
    
    public func refreshTextStorage(note: Note) {
        DispatchQueue.main.async {
            guard let pageController = UIApplication.shared.windows[0].rootViewController as? PageViewController,
                let viewController = pageController.orderedViewControllers[1] as? UINavigationController,
                let evc = viewController.viewControllers[0] as? EditorViewController
            else { return }
            
            evc.fill(note: note)
        }
    }

    private func calculateLabelMaxWidth() -> CGFloat {
        var width = CGFloat(0)

        for i in 0...4 {
            var j = 0

            while let cell = sidebarTableView.cellForRow(at: IndexPath(row: j, section: i)) as? SidebarTableCellView {

                if let font = cell.label.font, let text = cell.label.text {
                    let labelWidth = (text as NSString).size(withAttributes: [.font: font]).width

                    if labelWidth > width {
                        width = labelWidth
                    }
                }

                j += 1
            }

        }

        return width + 40
    }
}

