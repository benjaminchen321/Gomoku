import UIKit

class ViewController: UIViewController {

    // --- YOUR EXISTING OUTLETS (Keep these names) ---
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var boardView: UIView!
    // --- Assume you have the Reset Button Action connected ---
    // If you named the action differently, adjust the func name below

    @IBOutlet weak var resetButton: UIButton!
    // --- Game Constants ---
    let boardSize = 15 // Standard Gomoku size
    var cellSize: CGFloat = 0
    var boardPadding: CGFloat = 10 // Padding around the grid lines

    // --- Game State ---
    enum Player { case black, white }
    enum CellState { case empty, black, white }

    var currentPlayer: Player = .black
    var board: [[CellState]] = [] // 2D array representing the logical board state
    var gameOver = false

    // Store the visual pieces (simple views)
    var pieceViews: [[UIView?]] = []

    var backgroundGradientLayer: CAGradientLayer?
    // Add a property to hold the gradient layer
    var boardBackgroundLayer: CAGradientLayer?
    
    // Reference to the background layers if needed for removal on reset
    var woodBackgroundLayers: [CALayer] = []
    
    // --- Lifecycle Methods ---
    override func viewDidLoad() {
        super.viewDidLoad()
        setupMainBackground()
        styleStatusLabel()
        // Make sure the main view holding the board is clear initially
        boardView.backgroundColor = .clear
        // Draw the wood background first
        drawProceduralWoodBackground()
        styleResetButton()
        // Then setup the game (which might trigger layout and grid drawing)
        setupNewGame()
        addTapGestureRecognizer()
    }
    
    // --- NEW FUNCTION: Setup main background gradient ---
    func setupMainBackground() {
        // Remove old one if it exists (e.g., if called again on rotation)
        backgroundGradientLayer?.removeFromSuperlayer()

        let gradient = CAGradientLayer()
        gradient.frame = self.view.bounds // Use the main view's bounds

        // Subtle gradient - light gray to slightly darker gray (adjust as desired)
        let topColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).cgColor
        let bottomColor = UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1.0).cgColor
        gradient.colors = [topColor, bottomColor]

        // Vertical gradient
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)

        // Insert the gradient layer at the VERY BOTTOM (index 0) of the main view's layer hierarchy
        self.view.layer.insertSublayer(gradient, at: 0)
        self.backgroundGradientLayer = gradient // Store reference
    }
    
    func styleResetButton() {
        guard let button = resetButton else { return }

        // Colors (Keep or adjust as needed)
        let buttonBackgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        let buttonTextColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        let buttonBorderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 0.8) // Slightly lighter/softer border

        button.backgroundColor = buttonBackgroundColor
        button.setTitleColor(buttonTextColor, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

        // Layer Styling
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 0.75 // Thinner border
        button.layer.borderColor = buttonBorderColor.cgColor

        // Refined Shadow
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1) // Less vertical offset
        button.layer.shadowRadius = 2.5 // Slightly softer blur
        button.layer.shadowOpacity = 0.12 // More subtle opacity
        button.layer.masksToBounds = false

        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
    }

    // --- NEW FUNCTION: Style the status label ---
    func styleStatusLabel() {
        guard let label = statusLabel else { return }

        // Font: Choose a clean system font. "San Francisco" (SF) is the default.
        // Let's use a medium weight for slight emphasis. Adjust size as needed.
        label.font = UIFont.systemFont(ofSize: 22, weight: .medium)

        // Color: A dark, professional color (adjust if needed for contrast)
        label.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)

        // Alignment: Ensure it's centered
        label.textAlignment = .center

        // Optional: Subtle shadow for readability (use sparingly)
         label.layer.shadowColor = UIColor.black.cgColor
         label.layer.shadowOffset = CGSize(width: 0, height: 1)
         label.layer.shadowRadius = 2.0
         label.layer.shadowOpacity = 0.1
         label.layer.masksToBounds = false
    }

    func setupBoardBackground() {
        // Remove existing background layer if resetting
        boardBackgroundLayer?.removeFromSuperlayer()

        // Ensure boardView exists and Storyboard background is clear
        boardView.backgroundColor = .clear // Set in code or Storyboard

        let gradient = CAGradientLayer()
        gradient.frame = boardView.bounds // Will need updating if size changes!
        gradient.type = .axial
        // Example: Wood-like gradient (adjust colors as needed)
        let lightWood = UIColor(red: 0.85, green: 0.75, blue: 0.60, alpha: 1.0)
        let darkWood = UIColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1.0)
        gradient.colors = [lightWood.cgColor, darkWood.cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0) // Top-left
        gradient.endPoint = CGPoint(x: 1, y: 1)   // Bottom-right
        gradient.cornerRadius = 10 // Optional rounded corners
        gradient.borderWidth = 2 // Optional border
        gradient.borderColor = UIColor(white: 0.2, alpha: 1.0).cgColor

        boardView.layer.insertSublayer(gradient, at: 0) // Insert behind grid lines/pieces
        boardBackgroundLayer = gradient // Store reference
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // --- Update main background gradient frame ---
        self.backgroundGradientLayer?.frame = self.view.bounds
        
        // --- IMPORTANT: Update background layer frames if view size changes ---
        // This is crucial for rotation or complex layouts
        if !woodBackgroundLayers.isEmpty && woodBackgroundLayers.first?.frame.size != boardView.bounds.size {
            print("Adjusting wood background layer frames")
            // Redraw background if bounds changed significantly
            drawProceduralWoodBackground()
             // Redraw grid and pieces too
             if cellSize > 0 {
                 drawBoard()
                 redrawPieces()
             }
        }


        // --- Existing Layout Code ---
        let potentialCellSize = calculateCellSize()
        if cellSize != potentialCellSize && potentialCellSize > 0 {
             cellSize = potentialCellSize
             if !woodBackgroundLayers.isEmpty { // Ensure background exists before drawing board on top
                drawBoard() // Redraw grid if size changes
                redrawPieces() // Also redraw pieces if board size changes
             }
        } else if cellSize == 0 && potentialCellSize > 0 {
             // Initial draw case
             cellSize = potentialCellSize
             if !woodBackgroundLayers.isEmpty {
                drawBoard()
             }
        }
    }
    
    func drawProceduralWoodBackground() {
        // 1. Remove old background layers if they exist
        woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }
        woodBackgroundLayers.removeAll()

        // Ensure we have valid bounds to draw into
        guard boardView.bounds.width > 0 && boardView.bounds.height > 0 else {
            print("Skipping wood background draw: boardView bounds not ready.")
            return
        }
        print("Drawing procedural wood background into bounds: \(boardView.bounds)")

        // 2. Base Wood Color Layer
        let baseLayer = CALayer()
        baseLayer.frame = boardView.bounds
        // A medium, slightly desaturated brown
        baseLayer.backgroundColor = UIColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1.0).cgColor
        baseLayer.cornerRadius = 10 // Optional rounded corners
        baseLayer.masksToBounds = true // Clip grain layers to the bounds/corners
        boardView.layer.insertSublayer(baseLayer, at: 0) // Insert at the bottom
        woodBackgroundLayers.append(baseLayer)

        // 3. Simulate Wood Grain with Thin Layers
        let grainLayerCount = 35 // <<-- REDUCED count significantly
        let boardWidth = boardView.bounds.width
        let boardHeight = boardView.bounds.height

        for _ in 0..<grainLayerCount {
            let grainLayer = CALayer()

            // Grain Color Variation - make it less likely to go very dark
            let randomDarkness = CGFloat.random(in: -0.10...0.15) // Less dark variation
            let baseRed: CGFloat = 0.65
            let baseGreen: CGFloat = 0.50
            let baseBlue: CGFloat = 0.35
            let grainColor = UIColor(
                red: max(0.1, min(0.9, baseRed + randomDarkness)), // Adjusted base/range slightly
                green: max(0.1, min(0.9, baseGreen + randomDarkness)),
                blue: max(0.1, min(0.9, baseBlue + randomDarkness)),
                alpha: CGFloat.random(in: 0.1...0.35) // <<-- REDUCED alpha range (more transparent)
            )
            grainLayer.backgroundColor = grainColor.cgColor

            // Grain Shape & Position (Vertical Grain Example)
            let grainWidth = CGFloat.random(in: 1.5...4.0) // <<-- Slightly WIDER range
            let grainX = CGFloat.random(in: 0...(boardWidth - grainWidth))
            grainLayer.frame = CGRect(x: grainX, y: 0, width: grainWidth, height: boardHeight)

            baseLayer.addSublayer(grainLayer)
        }

        // 4. Subtle Lighting Gradient Overlay (Optional)
        let lightingGradient = CAGradientLayer()
        lightingGradient.frame = boardView.bounds
        lightingGradient.cornerRadius = baseLayer.cornerRadius // Match base layer's corners
        lightingGradient.type = .radial // Center highlight, darker edges
        lightingGradient.colors = [
            UIColor(white: 1.0, alpha: 0.15).cgColor, // Subtle white highlight in center
            UIColor(white: 1.0, alpha: 0.0).cgColor, // Fading out
            UIColor(white: 0.0, alpha: 0.15).cgColor // Subtle dark edges
        ]
        // Adjust locations for radial gradient spread
        lightingGradient.locations = [0.0, 0.6, 1.0]
        // Add ON TOP of the base layer + grain
        baseLayer.addSublayer(lightingGradient)

        // 5. Optional: Add a border around the whole board
        baseLayer.borderWidth = 2.0
        baseLayer.borderColor = UIColor(white: 0.1, alpha: 0.8).cgColor // Dark border
    }

    // --- Game Setup and Drawing ---
    func setupNewGame() {
        gameOver = false
        currentPlayer = .black
        statusLabel.text = "Black's Turn"
        board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize)

        // --- SAFER VIEW CLEANUP (Keep this) ---
        // Remove pieces first
        boardView.subviews.forEach { $0.removeFromSuperview() }
        // Then remove grid lines (CALayers added directly to boardView.layer)
        // We need to be careful NOT to remove our background base layer now!
        if let sublayers = boardView.layer.sublayers {
            // Only remove layers that are NOT the base wood layer OR its sublayers
            let layersToRemove = sublayers.filter { $0 != woodBackgroundLayers.first }
            layersToRemove.forEach { $0.removeFromSuperlayer() }
        }
        // Reset the pieceViews data structure
        pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
        // --- Reset cellSize to trigger redraw in viewDidLayoutSubviews ---
        cellSize = 0

        // --- Recalculate cell size ---
        // Don't reset cellSize here, let viewDidLayoutSubviews handle it
        // Just trigger layout
        boardView.setNeedsLayout()
        boardView.layoutIfNeeded()
    }

    func calculateCellSize() -> CGFloat {
         // Calculate cell size based on the current view's bounds
        guard boardView.bounds.width > 0, boardView.bounds.height > 0 else { return 0 }
        let boardDimension = min(boardView.bounds.width, boardView.bounds.height) - (boardPadding * 2)
        return boardDimension / CGFloat(boardSize - 1) // Use intersections, not cells
    }

     func drawBoard() {
         // --- Updated Layer Removal ---
         // We already removed layers in setupNewGame, so we just need to draw
         // If this function could be called independently, you'd need careful removal here too.
         // For now, assume setupNewGame cleared the old grid.

         guard cellSize > 0 else { return }
         guard let backgroundLayer = woodBackgroundLayers.first else {
            print("Cannot draw board: Wood background layer not found.")
            return
         }

         let boardDimension = cellSize * CGFloat(boardSize - 1)
         let gridLineColor = UIColor(white: 0.1, alpha: 0.5).cgColor // Darker, less transparent grid
         let gridLineWidth: CGFloat = 0.75

         for i in 0..<boardSize {
             // Vertical lines
             let vLayer = CALayer()
             let xPos = boardPadding + CGFloat(i) * cellSize
             vLayer.frame = CGRect(x: xPos - (gridLineWidth / 2), y: boardPadding, width: gridLineWidth, height: boardDimension)
             vLayer.backgroundColor = gridLineColor
             // --- IMPORTANT: Add grid lines to the boardView's main layer, *above* the background ---
             boardView.layer.addSublayer(vLayer)

             // Horizontal lines
             let hLayer = CALayer()
             let yPos = boardPadding + CGFloat(i) * cellSize
             hLayer.frame = CGRect(x: boardPadding, y: yPos - (gridLineWidth / 2), width: boardDimension, height: gridLineWidth)
             hLayer.backgroundColor = gridLineColor
             // --- Add grid lines to the boardView's main layer ---
             boardView.layer.addSublayer(hLayer)
         }
         print("Board drawn with cell size: \(cellSize)")
     }

    // Redraw pieces if orientation changes, for example
    func redrawPieces() {
        guard cellSize > 0 else { return }
        // Remove existing piece UIViews first
        pieceViews.flatMap { $0 }.forEach { $0?.removeFromSuperview() }

        // Redraw based on the logical board state
        for r in 0..<boardSize {
            for c in 0..<boardSize {
                if board[r][c] == .black {
                    drawPiece(atRow: r, col: c, player: .black)
                } else if board[r][c] == .white {
                    drawPiece(atRow: r, col: c, player: .white)
                }
            }
        }
    }


    // --- Tap Handling & Game Logic ---
    func addTapGestureRecognizer() {
        guard let currentBoardView = boardView else {
            print("FATAL ERROR: boardView outlet is NIL when addTapGestureRecognizer is called!")
            return
        }
        // Print initial state for clarity
        print("addTapGestureRecognizer: boardView confirmed NOT nil. Initial recognizers: \(currentBoardView.gestureRecognizers ?? [])")

        // --- Force Removal of OLD Tap Recognizers ---
        // Iterate through existing recognizers and remove any that are specifically UITapGestureRecognizer
        if let existingRecognizers = currentBoardView.gestureRecognizers {
            for recognizer in existingRecognizers {
                if recognizer is UITapGestureRecognizer {
                    print("--> Removing existing UITapGestureRecognizer.")
                    currentBoardView.removeGestureRecognizer(recognizer)
                }
            }
        }

        // --- Add the desired recognizer ---
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        currentBoardView.addGestureRecognizer(tap)
        print("--> NEW Tap Gesture Recognizer ADDED.")

        // --- Log final state ---
        print("boardView FINAL gestureRecognizers count: \(currentBoardView.gestureRecognizers?.count ?? 0)")
        if let recognizers = currentBoardView.gestureRecognizers {
            print("Final Recognizers on boardView: \(recognizers)")
        }
    }

    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        print("--- handleTap CALLED ---")
        guard !gameOver, cellSize > 0 else {
            print("Guard FAILED: gameOver=\(gameOver), cellSize=\(cellSize)")
            return
        }

        let location = sender.location(in: boardView)
        print("Tap location in view: \(location)") // <-- ADD THIS LINE

        // Convert tap location to grid coordinates (Nearest Intersection)
        let tappedColFloat = (location.x - boardPadding) / cellSize
        let tappedRowFloat = (location.y - boardPadding) / cellSize
        print("Calculated float coords: (col: \(tappedColFloat), row: \(tappedRowFloat))") // <-- ADD THIS LINE

        // Check if tap is reasonably close to an intersection point (e.g., within 40% of cellSize)
        let colDiff = abs(tappedColFloat - round(tappedColFloat))
        let rowDiff = abs(tappedRowFloat - round(tappedRowFloat))
        print("Intersection proximity check: colDiff=\(colDiff), rowDiff=\(rowDiff) (Needs < 0.4)") // <-- ADD THIS LINE
        guard colDiff < 0.4 && rowDiff < 0.4 else {
             print("Guard FAILED: Tap too far from intersection.") // <-- ADD THIS LINE
             return
        }

        let tappedCol = Int(round(tappedColFloat))
        let tappedRow = Int(round(tappedRowFloat))
        print("Rounded integer coords: (col: \(tappedCol), row: \(tappedRow))") // <-- ADD THIS LINE


        // Validate coordinates
        print("Checking bounds (0-\(boardSize-1)): row=\(tappedRow), col=\(tappedCol)") // <-- ADD THIS LINE
        guard tappedRow >= 0 && tappedRow < boardSize && tappedCol >= 0 && tappedCol < boardSize else {
            print("Guard FAILED: Tap out of bounds.") // <-- ADD THIS LINE
            return
        }

        // Check if cell is empty
        print("Checking if empty at [\(tappedRow)][\(tappedCol)]: Current state = \(board[tappedRow][tappedCol])") // <-- ADD THIS LINE
        guard board[tappedRow][tappedCol] == .empty else {
            print("Guard FAILED: Cell already occupied.") // <-- ADD THIS LINE
            return
        }

        print("All guards passed. Placing piece...") // <-- ADD THIS LINE
        // Place the piece
        placePiece(atRow: tappedRow, col: tappedCol)
    }

    func placePiece(atRow row: Int, col: Int) {
        let pieceState: CellState = (currentPlayer == .black) ? .black : .white
        board[row][col] = pieceState // Update logical board

        // Draw the piece visually
        drawPiece(atRow: row, col: col, player: currentPlayer)

        // Check for win
        if checkForWin(playerState: pieceState, lastRow: row, lastCol: col) {
            gameOver = true
            statusLabel.text = "\(currentPlayer == .black ? "Black" : "White") Wins!" // More explicit win message
            print("\(currentPlayer) Wins!")
        } else if isBoardFull() { // Check for draw
            gameOver = true
            statusLabel.text = "Draw!"
            print("Draw!")
        } else {
            // Switch player
            switchPlayer()
        }
    }

    func drawPiece(atRow row: Int, col: Int, player: Player) {
        guard cellSize > 0 else { return }

        let pieceSize = cellSize * 0.85 // Slightly larger piece
        let x = boardPadding + CGFloat(col) * cellSize - (pieceSize / 2)
        let y = boardPadding + CGFloat(row) * cellSize - (pieceSize / 2)
        let pieceFrame = CGRect(x: x, y: y, width: pieceSize, height: pieceSize)

        let pieceView = UIView(frame: pieceFrame)
        pieceView.backgroundColor = .clear // Make background clear to see gradient

        // --- Gradient Layer for Depth ---
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = pieceView.bounds
        gradientLayer.cornerRadius = pieceSize / 2
        gradientLayer.type = .radial // Make it look rounded

        // Define colors based on player
        let lightColor: UIColor
        let darkColor: UIColor
        if player == .black {
            lightColor = UIColor(white: 0.3, alpha: 1.0) // Dark gray
            darkColor = UIColor(white: 0.05, alpha: 1.0) // Near black
        } else { // White piece
            lightColor = UIColor(white: 0.95, alpha: 1.0) // Off-white
            darkColor = UIColor(white: 0.75, alpha: 1.0) // Light gray
        }
        gradientLayer.colors = [lightColor.cgColor, darkColor.cgColor]

        // Adjust gradient start/end points for a top-left highlight effect
        gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.25) // Near top-left
        gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.75)   // Towards bottom-right

        pieceView.layer.addSublayer(gradientLayer)
        pieceView.layer.cornerRadius = pieceSize / 2 // Ensure clipping

        // --- Subtle Border ---
        pieceView.layer.borderWidth = 0.5 // Thinner border
        pieceView.layer.borderColor = (player == .black) ? UIColor(white: 0.5, alpha: 0.7).cgColor : UIColor(white: 0.6, alpha: 0.7).cgColor

        // --- Shadow for Lifting Effect ---
        pieceView.layer.shadowColor = UIColor.black.cgColor
        pieceView.layer.shadowOpacity = 0.4 // Opacity of shadow
        pieceView.layer.shadowOffset = CGSize(width: 1, height: 2) // Offset down and right
        pieceView.layer.shadowRadius = 2.0 // Blur radius of shadow
        pieceView.layer.masksToBounds = false // IMPORTANT: Allow shadow to be visible outside bounds

        // Remove previous piece view at this position if it exists
        pieceViews[row][col]?.removeFromSuperview()

        boardView.addSubview(pieceView)
        pieceViews[row][col] = pieceView
    }

    func switchPlayer() {
        currentPlayer = (currentPlayer == .black) ? .white : .black
        statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn" // Explicit player name
    }

    func isBoardFull() -> Bool {
        // Check if any cell is still empty
        for r in 0..<boardSize {
            for c in 0..<boardSize {
                if board[r][c] == .empty {
                    return false
                }
            }
        }
        return true // No empty cells found
    }

    // --- Win Condition Check ---
    func checkForWin(playerState: CellState, lastRow: Int, lastCol: Int) -> Bool {
        let directions = [
            (0, 1),  // Horizontal -> (dr, dc)
            (1, 0),  // Vertical
            (1, 1),  // Diagonal \
            (1, -1) // Diagonal /
        ]

        for (dr, dc) in directions {
            var count = 1 // Count includes the piece just placed

            // Check in one direction (e.g., right, down, down-right, down-left)
            for i in 1..<5 { // Check up to 4 steps away
                let checkRow = lastRow + dr * i
                let checkCol = lastCol + dc * i
                if checkBounds(row: checkRow, col: checkCol) && board[checkRow][checkCol] == playerState {
                    count += 1
                } else {
                    break // Stop counting in this direction if out of bounds or wrong color
                }
            }

            // Check in the opposite direction (e.g., left, up, up-left, up-right)
            for i in 1..<5 { // Check up to 4 steps away
                let checkRow = lastRow - dr * i
                let checkCol = lastCol - dc * i
                 if checkBounds(row: checkRow, col: checkCol) && board[checkRow][checkCol] == playerState {
                    count += 1
                } else {
                    break // Stop counting in this direction if out of bounds or wrong color
                }
            }

            // Did we find 5 or more in a row?
            if count >= 5 {
                return true
            }
        }

        return false // No win found in any direction
    }

    func checkBounds(row: Int, col: Int) -> Bool {
        return row >= 0 && row < boardSize && col >= 0 && col < boardSize
    }


    // Keep the action connected to TOUCH DOWN now
    @IBAction func resetButtonTapped(_ sender: UIButton) {
        print("Reset button DOWN")

        // --- Animate DOWN immediately ---
        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
             // Scale down instantly on touch
             sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
             // Optional: Slightly fade out
             // sender.alpha = 0.8
        }, completion: nil) // No completion block needed here

         // --- IMPORTANT: Reset Game Logic ---
         // Do the actual game reset logic here when touch goes DOWN.
         // setupNewGame() call remains here if you want the reset triggered instantly on press.
         setupNewGame()

         // --- Add a target for Touch Up events to reset the visual state ---
         // We need to know when the finger lifts UP (inside or outside) to animate back.
         // We add these targets programmatically here.
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpInside)
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpOutside)
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchCancel) // Handle cancellation too
    }

    @IBAction func resetButtonReleased(_ sender: UIButton) {
        print("Reset button RELEASED")
        // Animate back to normal state when finger lifts up
        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
            sender.transform = .identity
            // Optional: Fade back in
            // sender.alpha = 1.0
        }, completion: { _ in
            // --- IMPORTANT: Remove the dynamically added targets ---
            // Otherwise, they stack up every time the button is pressed.
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside)
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside)
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)
        })
    }

} // End of ViewController class
