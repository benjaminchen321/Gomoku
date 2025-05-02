import UIKit

class ViewController: UIViewController {

    // --- Outlets ---
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var boardView: UIView!
    @IBOutlet weak var resetButton: UIButton!

    // --- Game Constants ---
    let boardSize = 15
    var cellSize: CGFloat = 0
    var boardPadding: CGFloat = 10

    // --- Game State ---
    enum Player { case black, white }
    enum CellState { case empty, black, white }
    var currentPlayer: Player = .black
    var board: [[CellState]] = []
    var gameOver = false
    var pieceViews: [[UIView?]] = []

    // --- Layer References ---
    var backgroundGradientLayer: CAGradientLayer?
    var woodBackgroundLayers: [CALayer] = []
    private var lastDrawnBoardBounds: CGRect = .zero

    // --- Lifecycle Methods ---
    override func viewDidLoad() {
        super.viewDidLoad()
        print("viewDidLoad starting...")

        // Style elements first
        setupMainBackground()
        styleStatusLabel()
        boardView.backgroundColor = .clear
        styleResetButton()

        // Define PROGRAMMATIC constraints (Simplified Set)
        setupConstraints()

        // Initialize game state & add gesture
        setupNewGame() // Resets cellSize=0
        addTapGestureRecognizer()

        // Force initial layout calculation AFTER constraints are set
        print("viewDidLoad: Forcing layout with layoutIfNeeded...")
        view.layoutIfNeeded()

        print("viewDidLoad completed.")
    }

    // --- viewDidLayoutSubviews (Keep simplified redraw trigger) ---
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        print("viewDidLayoutSubviews triggered.")

        self.backgroundGradientLayer?.frame = self.view.bounds // Update main background

        let currentBoardBounds = boardView.bounds
        print("viewDidLayoutSubviews - BoardView Bounds: \(currentBoardBounds)")

        guard currentBoardBounds.width > 0, currentBoardBounds.height > 0 else {
            print("viewDidLayoutSubviews: boardView bounds zero or invalid, skipping.")
            if lastDrawnBoardBounds != .zero { lastDrawnBoardBounds = .zero } // Reset if bounds become invalid
            return
        }

        // *** Redraw ONLY if the bounds have actually changed ***
        if currentBoardBounds != lastDrawnBoardBounds {
            print("--> Board bounds changed (\(lastDrawnBoardBounds) -> \(currentBoardBounds)). Performing visual update.")

            let newCellSize = calculateCellSize()
            guard newCellSize > 0 else {
                print("viewDidLayoutSubviews: Calculated cell size is zero, cannot draw.")
                return
            }
            self.cellSize = newCellSize

            drawProceduralWoodBackground()
            drawBoard()
            redrawPieces()

            lastDrawnBoardBounds = currentBoardBounds // Update after successful draw
            print("viewDidLayoutSubviews: Visual update complete with cellSize: \(self.cellSize)")
        } else {
            print("viewDidLayoutSubviews: Board bounds haven't changed, no redraw needed.")
        }
    }

    // --- FIXED Constraint Setup ---
    func setupConstraints() {
        guard let statusLabel = statusLabel, let boardView = boardView, let resetButton = resetButton else {
            print("Error: Outlets not connected!")
            return
        }
        print("Setting up fixed constraints...")

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        boardView.translatesAutoresizingMaskIntoConstraints = false
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        let safeArea = view.safeAreaLayoutGuide

        // Clear any existing constraints
        boardView.removeConstraints(boardView.constraints)
        
        // Status label constraints
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),
            statusLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)
        ])

        // Board view constraints - The key fix:
        // 1. Center the board in available space
        // 2. Maintain square aspect ratio
        // 3. Ensure board is within safe area with margins
        // 4. Size based on available space with priority system
        
        // First create all constraints but don't activate them yet
        let centerXConstraint = boardView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)
        let centerYConstraint = boardView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        
        // This is the key constraint - ensure board remains square
        let aspectRatioConstraint = boardView.heightAnchor.constraint(equalTo: boardView.widthAnchor, multiplier: 1.0)
        aspectRatioConstraint.priority = .required // 1000 - this must be satisfied
        
        // Margins - ensure board never touches edges
        let leadingConstraint = boardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20)
        let trailingConstraint = boardView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20)
        let topConstraint = boardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 80) // More space for status label
        let bottomConstraint = boardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -80) // More space for reset button
        
        // Size constraints - try to make board as large as possible while respecting margins
        // Width constraint - high but not required priority
        let widthConstraint = boardView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -40)
        widthConstraint.priority = .defaultHigh // 750
        
        // Height constraint - high but not required priority
        let heightConstraint = boardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -160)
        heightConstraint.priority = .defaultHigh // 750
        
        // Activate all constraints
        NSLayoutConstraint.activate([
            centerXConstraint,
            centerYConstraint,
            aspectRatioConstraint,
            leadingConstraint,
            trailingConstraint,
            topConstraint,
            bottomConstraint,
            widthConstraint,
            heightConstraint
        ])

        // Reset button constraints
        NSLayoutConstraint.activate([
            resetButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -30),
            resetButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            resetButton.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 30),
            resetButton.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -30)
        ])

        print("Fixed constraints activated.")
    }

    // --- Styling Functions (Keep As Is) ---
    func setupMainBackground() { /* ... */
        backgroundGradientLayer?.removeFromSuperlayer(); let gradient = CAGradientLayer(); gradient.frame = self.view.bounds
        let topColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).cgColor; let bottomColor = UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1.0).cgColor
        gradient.colors = [topColor, bottomColor]; gradient.startPoint = CGPoint(x: 0.5, y: 0.0); gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.view.layer.insertSublayer(gradient, at: 0); self.backgroundGradientLayer = gradient
    }
    func styleResetButton() { /* ... */
        guard let button = resetButton else { return }; let bgColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0); let textColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0); let borderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 0.8)
        button.backgroundColor = bgColor; button.setTitleColor(textColor, for: .normal); button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        button.layer.cornerRadius = 8; button.layer.borderWidth = 0.75; button.layer.borderColor = borderColor.cgColor; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
    }
    func styleStatusLabel() { /* ... */
         guard let label = statusLabel else { return }; label.font = UIFont.systemFont(ofSize: 22, weight: .medium); label.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0); label.textAlignment = .center
         label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOffset = CGSize(width: 0, height: 1); label.layer.shadowRadius = 2.0; label.layer.shadowOpacity = 0.1; label.layer.masksToBounds = false
    }

    // --- Drawing Functions (Keep As Is) ---
    func drawProceduralWoodBackground() { /* ... */
         woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll()
         guard boardView.bounds.width > 0 && boardView.bounds.height > 0 else { print("Skipping wood background draw: boardView bounds not ready."); return }
         print("Drawing procedural wood background into bounds: \(boardView.bounds)"); let baseLayer = CALayer(); baseLayer.frame = boardView.bounds; baseLayer.backgroundColor = UIColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1.0).cgColor; baseLayer.cornerRadius = 10; baseLayer.masksToBounds = true
         boardView.layer.insertSublayer(baseLayer, at: 0); woodBackgroundLayers.append(baseLayer); let grainLayerCount = 35; let boardWidth = boardView.bounds.width; let boardHeight = boardView.bounds.height
         for _ in 0..<grainLayerCount { let grainLayer = CALayer(); let randomDarkness = CGFloat.random(in: -0.10...0.15); let baseRed: CGFloat = 0.65; let baseGreen: CGFloat = 0.50; let baseBlue: CGFloat = 0.35; let grainColor = UIColor(red: max(0.1, min(0.9, baseRed + randomDarkness)), green: max(0.1, min(0.9, baseGreen + randomDarkness)), blue: max(0.1, min(0.9, baseBlue + randomDarkness)), alpha: CGFloat.random(in: 0.1...0.35)); grainLayer.backgroundColor = grainColor.cgColor; let grainWidth = CGFloat.random(in: 1.5...4.0); let grainX = CGFloat.random(in: 0...(boardWidth - grainWidth)); grainLayer.frame = CGRect(x: grainX, y: 0, width: grainWidth, height: boardHeight); baseLayer.addSublayer(grainLayer) }
         let lightingGradient = CAGradientLayer(); lightingGradient.frame = boardView.bounds; lightingGradient.cornerRadius = baseLayer.cornerRadius; lightingGradient.type = .radial; lightingGradient.colors = [UIColor(white: 1.0, alpha: 0.15).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.15).cgColor]; lightingGradient.locations = [0.0, 0.6, 1.0]; baseLayer.addSublayer(lightingGradient); baseLayer.borderWidth = 2.0; baseLayer.borderColor = UIColor(white: 0.1, alpha: 0.8).cgColor
    }
    func drawBoard() { /* ... */
         boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }
         guard cellSize > 0 else { print("Skipping drawBoard: cellSize is 0"); return }
         guard woodBackgroundLayers.first != nil else { print("Cannot draw board: Wood background layer not found."); return }
         let boardDimension = cellSize * CGFloat(boardSize - 1); let gridLineColor = UIColor(white: 0.1, alpha: 0.65).cgColor; let gridLineWidth: CGFloat = 0.75
         for i in 0..<boardSize { let vLayer = CALayer(); let xPos = boardPadding + CGFloat(i) * cellSize; vLayer.frame = CGRect(x: xPos - (gridLineWidth / 2), y: boardPadding, width: gridLineWidth, height: boardDimension); vLayer.backgroundColor = gridLineColor; vLayer.name = "gridLine"; boardView.layer.addSublayer(vLayer); let hLayer = CALayer(); let yPos = boardPadding + CGFloat(i) * cellSize; hLayer.frame = CGRect(x: boardPadding, y: yPos - (gridLineWidth / 2), width: boardDimension, height: gridLineWidth); hLayer.backgroundColor = gridLineColor; hLayer.name = "gridLine"; boardView.layer.addSublayer(hLayer) }
         print("Board drawn with cell size: \(cellSize)")
    }
    func redrawPieces() { /* ... */
         guard cellSize > 0 else { print("Skipping redrawPieces: cellSize is 0"); return }
         boardView.subviews.forEach { $0.removeFromSuperview() }
         for r in 0..<boardSize { for c in 0..<boardSize { let cellState = board[r][c]; if cellState == .black || cellState == .white { drawPiece(atRow: r, col: c, player: (cellState == .black) ? .black : .white)}}}
    }
    func drawPiece(atRow row: Int, col: Int, player: Player) { /* ... */
         guard cellSize > 0 else { return }
         let pieceSize = cellSize * 0.85; let x = boardPadding + CGFloat(col) * cellSize - (pieceSize / 2); let y = boardPadding + CGFloat(row) * cellSize - (pieceSize / 2); let pieceFrame = CGRect(x: x, y: y, width: pieceSize, height: pieceSize)
         let pieceView = UIView(frame: pieceFrame); pieceView.backgroundColor = .clear
         let gradientLayer = CAGradientLayer(); gradientLayer.frame = pieceView.bounds; gradientLayer.cornerRadius = pieceSize / 2; gradientLayer.type = .radial
         let lightColor: UIColor; let darkColor: UIColor
         if player == .black { lightColor = UIColor(white: 0.3, alpha: 1.0); darkColor = UIColor(white: 0.05, alpha: 1.0) } else { lightColor = UIColor(white: 0.95, alpha: 1.0); darkColor = UIColor(white: 0.75, alpha: 1.0) }
         gradientLayer.colors = [lightColor.cgColor, darkColor.cgColor]; gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.25); gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.75)
         pieceView.layer.addSublayer(gradientLayer); pieceView.layer.cornerRadius = pieceSize / 2; pieceView.layer.borderWidth = 0.5
         pieceView.layer.borderColor = (player == .black) ? UIColor(white: 0.5, alpha: 0.7).cgColor : UIColor(white: 0.6, alpha: 0.7).cgColor
         pieceView.layer.shadowColor = UIColor.black.cgColor; pieceView.layer.shadowOpacity = 0.4; pieceView.layer.shadowOffset = CGSize(width: 1, height: 2); pieceView.layer.shadowRadius = 2.0; pieceView.layer.masksToBounds = false
         pieceViews[row][col]?.removeFromSuperview(); boardView.addSubview(pieceView); pieceViews[row][col] = pieceView
    }

    // --- Game Logic & Interaction (Keep As Is) ---
    func setupNewGame() { /* ... ensure cellSize = 0 ... */
        gameOver = false; currentPlayer = .black; statusLabel.text = "Black's Turn"; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize)
        boardView.subviews.forEach { $0.removeFromSuperview() }
        boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }
        // We don't necessarily need to remove wood background here, viewDidLayoutSubviews handles it if bounds change
        pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        cellSize = 0 // CRITICAL!
        print("setupNewGame: Reset cellSize to 0.")
        // Trigger layout pass AFTER resetting cell size
        view.setNeedsLayout()
    }
    func calculateCellSize() -> CGFloat { /* ... unchanged ... */
        guard boardView.bounds.width > 0, boardView.bounds.height > 0 else { return 0 }
        let boardDimension = min(boardView.bounds.width, boardView.bounds.height) - (boardPadding * 2)
        guard boardSize > 1 else { return boardDimension }
        return boardDimension / CGFloat(boardSize - 1)
    }
    func addTapGestureRecognizer() { /* ... unchanged ... */
        guard let currentBoardView = boardView else { print("FATAL ERROR: boardView outlet is NIL..."); return }
        print("addTapGestureRecognizer: boardView confirmed NOT nil. Initial recognizers: \(currentBoardView.gestureRecognizers ?? [])")
        if let existingRecognizers = currentBoardView.gestureRecognizers { for recognizer in existingRecognizers { if recognizer is UITapGestureRecognizer { print("--> Removing existing UITapGestureRecognizer."); currentBoardView.removeGestureRecognizer(recognizer) }}}
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))); currentBoardView.addGestureRecognizer(tap); print("--> NEW Tap Gesture Recognizer ADDED.")
        print("boardView FINAL gestureRecognizers count: \(currentBoardView.gestureRecognizers?.count ?? 0)")
        if let recognizers = currentBoardView.gestureRecognizers { print("Final Recognizers on boardView: \(recognizers)") }
    }
    @objc func handleTap(_ sender: UITapGestureRecognizer) { /* ... unchanged ... */
         print("--- handleTap CALLED ---"); guard !gameOver, cellSize > 0 else { print("Guard FAILED: gameOver=\(gameOver), cellSize=\(cellSize)"); return }
         let location = sender.location(in: boardView); print("Tap location in view: \(location)")
         let tappedColFloat = (location.x - boardPadding) / cellSize; let tappedRowFloat = (location.y - boardPadding) / cellSize; print("Calculated float coords: (col: \(tappedColFloat), row: \(tappedRowFloat))")
         let colDiff = abs(tappedColFloat - round(tappedColFloat)); let rowDiff = abs(tappedRowFloat - round(tappedRowFloat)); print("Intersection proximity check: colDiff=\(colDiff), rowDiff=\(rowDiff) (Needs < 0.4)")
         guard colDiff < 0.4 && rowDiff < 0.4 else { print("Guard FAILED: Tap too far from intersection."); return }
         let tappedCol = Int(round(tappedColFloat)); let tappedRow = Int(round(tappedRowFloat)); print("Rounded integer coords: (col: \(tappedCol), row: \(tappedRow))")
         print("Checking bounds (0-\(boardSize-1)): row=\(tappedRow), col=\(tappedCol)")
         guard checkBounds(row: tappedRow, col: tappedCol) else { print("Guard FAILED: Tap out of bounds."); return }
         print("Checking if empty at [\(tappedRow)][\(tappedCol)]: Current state = \(board[tappedRow][tappedCol])")
         guard board[tappedRow][tappedCol] == .empty else { print("Guard FAILED: Cell already occupied."); return }
         print("All guards passed. Placing piece..."); placePiece(atRow: tappedRow, col: tappedCol)
    }
    func placePiece(atRow row: Int, col: Int) { /* ... unchanged ... */
         let pieceState: CellState = (currentPlayer == .black) ? .black : .white; board[row][col] = pieceState
         drawPiece(atRow: row, col: col, player: currentPlayer)
         if checkForWin(playerState: pieceState, lastRow: row, lastCol: col) { gameOver = true; statusLabel.text = "\(currentPlayer == .black ? "Black" : "White") Wins!"; print("\(currentPlayer) Wins!") }
         else if isBoardFull() { gameOver = true; statusLabel.text = "Draw!"; print("Draw!") }
         else { switchPlayer() }
    }
    func switchPlayer() { /* ... unchanged ... */
         currentPlayer = (currentPlayer == .black) ? .white : .black; statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn"
    }
    func isBoardFull() -> Bool { /* ... unchanged ... */
         for row in board { if row.contains(.empty) { return false } }; return true
    }
    func checkForWin(playerState: CellState, lastRow: Int, lastCol: Int) -> Bool { /* ... unchanged ... */
         let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var count = 1
             for i in 1..<5 { let checkRow = lastRow + dr * i; let checkCol = lastCol + dc * i; if checkBounds(row: checkRow, col: checkCol) && board[checkRow][checkCol] == playerState { count += 1 } else { break } }
             for i in 1..<5 { let checkRow = lastRow - dr * i; let checkCol = lastCol - dc * i; if checkBounds(row: checkRow, col: checkCol) && board[checkRow][checkCol] == playerState { count += 1 } else { break } }
             if count >= 5 { return true } }; return false
    }
    func checkBounds(row: Int, col: Int) -> Bool { /* ... unchanged ... */
         return row >= 0 && row < boardSize && col >= 0 && col < boardSize
    }
    @IBAction func resetButtonTapped(_ sender: UIButton) { /* ... unchanged ... */
         print("Reset button DOWN"); UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: { sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }, completion: nil)
         setupNewGame()
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpInside); sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpOutside); sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchCancel)
    }
    @IBAction func resetButtonReleased(_ sender: UIButton) { /* ... unchanged ... */
         print("Reset button RELEASED"); UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: { sender.transform = .identity }, completion: { _ in sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside); sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside); sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)})
    }

} // End of ViewController class
