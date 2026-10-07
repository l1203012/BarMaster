import AppKit

/// A scrollable strip of tab titles; tapping one selects that tab.
final class TabScrubberItem: NSCustomTouchBarItem, NSScrubberDataSource, NSScrubberDelegate {
    private static let itemID = NSUserInterfaceItemIdentifier("tab")
    private let scrubber = NSScrubber()
    private var titles: [String] = []
    /// Called with the 0-based index of the tapped tab.
    var onSelect: ((Int) -> Void)?

    init(identifier: NSTouchBarItem.Identifier, width: CGFloat = 230) {
        super.init(identifier: identifier)
        scrubber.register(NSScrubberTextItemView.self, forItemIdentifier: Self.itemID)
        scrubber.mode = .free
        scrubber.selectionBackgroundStyle = .roundedBackground
        scrubber.selectionOverlayStyle = .outlineOverlay
        let layout = NSScrubberFlowLayout()
        layout.itemSpacing = 4
        layout.itemSize = NSSize(width: 110, height: 30)
        scrubber.scrubberLayout = layout
        scrubber.dataSource = self
        scrubber.delegate = self
        scrubber.widthAnchor.constraint(equalToConstant: width).isActive = true
        view = scrubber
        customizationLabel = "Tabs"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func update(titles: [String], selected: Int) {
        self.titles = titles
        scrubber.reloadData()
        guard titles.indices.contains(selected) else { return }
        // Selecting before the new items are laid out is silently dropped.
        scrubber.layoutSubtreeIfNeeded()
        scrubber.selectedIndex = selected
        scrubber.scrollItem(at: selected, to: .center)
    }

    func numberOfItems(for scrubber: NSScrubber) -> Int {
        titles.count
    }

    func scrubber(_ scrubber: NSScrubber, viewForItemAt index: Int) -> NSScrubberItemView {
        let view = scrubber.makeItem(withIdentifier: Self.itemID, owner: nil) as? NSScrubberTextItemView
            ?? NSScrubberTextItemView()
        view.title = titles[index]
        return view
    }

    func scrubber(_ scrubber: NSScrubber, didSelectItemAt selectedIndex: Int) {
        onSelect?(selectedIndex)
    }
}
