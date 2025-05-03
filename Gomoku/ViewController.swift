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

    // --- AI Control ---
    let aiPlayer: Player = .white
    var isAiTurn: Bool { currentGameMode == .humanVsAI && currentPlayer == aiPlayer }

    // --- Layer References ---
    var backgroundGradientLayer: CAGradientLayer?
    var woodBackgroundLayers: [CALayer] = []
    private var lastDrawnBoardBounds: CGRect = .zero

    // --- Game Setup State ---
    enum GameState { case setup, playing }
    enum GameMode { case humanVsHuman, humanVsAI }
    private var currentGameState: GameState = .setup
    private var currentGameMode: GameMode = .humanVsHuman

    // --- Setup UI Elements ---
    private let gameTitleLabel = UILabel()      // NEW: Game Title
    private let setupTitleLabel = UILabel()
    private let startHvsAIButton = UIButton(type: .system)
    private let startHvsHButton = UIButton(type: .system)
    private var setupUIElements: [UIView] = []

    // --- NEW: Main Menu Button ---
    private let mainMenuButton = UIButton(type: .system)

    // --- Constraint Activation Flag ---
    private var constraintsActivated = false

    // --- Lifecycle Methods ---
    override func viewDidLoad() {
        super.viewDidLoad()
        print("viewDidLoad starting...")

        // Style elements first
        setupMainBackground()
        styleStatusLabel()
        boardView.backgroundColor = .clear
        styleResetButton()
        createMainMenuButton() // Create before constraints

        // Create Setup UI Elements
        createSetupUI()

        // Initialize game state & add gesture (but don't draw board yet)
        setupNewGameVariablesOnly()
        // addTapGestureRecognizer() // Add only when game starts

        // Show Setup UI Initially
        showSetupUI()

        print("viewDidLoad completed.")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Setup constraints ONCE before the first layout pass
        if !constraintsActivated {
            print("viewWillLayoutSubviews: Setting up ALL constraints for the first time.")
            setupConstraints() // For Game Elements
            setupSetupUIConstraints() // For Setup UI
            setupMainMenuButtonConstraints() // For Main Menu Button
            constraintsActivated = true
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        print("viewDidLayoutSubviews triggered. State: \(currentGameState)")

        // Update full screen background gradient frame always
        self.backgroundGradientLayer?.frame = self.view.bounds

        // Only perform board drawing if in the 'playing' state
        guard currentGameState == .playing else {
            print("viewDidLayoutSubviews: Not in playing state, skipping board draw.")
            return
        }

        let currentBoardBounds = boardView.bounds
        print("viewDidLayoutSubviews - BoardView Bounds: \(currentBoardBounds)")

        guard currentBoardBounds.width > 0, currentBoardBounds.height > 0 else {
            print("viewDidLayoutSubviews: boardView bounds zero or invalid, skipping draw.")
            if lastDrawnBoardBounds != .zero { lastDrawnBoardBounds = .zero }
            return
        }

        let potentialCellSize = calculateCellSize()
        print("viewDidLayoutSubviews - Potential Cell Size: \(potentialCellSize)")
        guard potentialCellSize > 0 else {
            print("viewDidLayoutSubviews: Potential cell size calculation invalid, skipping draw.")
            if lastDrawnBoardBounds != .zero { lastDrawnBoardBounds = .zero }
            return
        }

        // Redraw ONLY if the bounds have actually changed OR if cellSize was reset
        if currentBoardBounds != lastDrawnBoardBounds || self.cellSize == 0 {
            print("--> Board bounds changed or initial draw needed. Performing visual update.")
            self.cellSize = potentialCellSize
            drawProceduralWoodBackground()
            drawBoard()
            redrawPieces()
            lastDrawnBoardBounds = currentBoardBounds
            print("viewDidLayoutSubviews: Visual update complete with cellSize: \(self.cellSize)")
        } else {
            print("viewDidLayoutSubviews: Board bounds haven't changed, no redraw needed.")
        }
    }

    // --- Constraint Setup (YOUR WORKING VERSION - UNCHANGED for game elements) ---
    func setupConstraints() {
        guard let statusLabel = statusLabel, let boardView = boardView, let resetButton = resetButton else {
            print("Error: Outlets not connected for game elements!")
            return
        }
        print("Setting up game element constraints...")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        boardView.translatesAutoresizingMaskIntoConstraints = false
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        let safeArea = view.safeAreaLayoutGuide

        // Board view constraints (Your working fixed version)
        let centerXConstraint = boardView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)
        let centerYConstraint = boardView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        let aspectRatioConstraint = boardView.heightAnchor.constraint(equalTo: boardView.widthAnchor, multiplier: 1.0); aspectRatioConstraint.priority = .required
        let leadingConstraint = boardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20)
        let trailingConstraint = boardView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20)
        let topConstraint = boardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 80) // Adjusted margin
        let bottomConstraint = boardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -80) // Adjusted margin
        let widthConstraint = boardView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -40); widthConstraint.priority = .defaultHigh
        let heightConstraint = boardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -160); heightConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            centerXConstraint, centerYConstraint, aspectRatioConstraint,
            leadingConstraint, trailingConstraint, topConstraint, bottomConstraint,
            widthConstraint, heightConstraint
        ])

        // Status label constraints
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),
            statusLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)
        ])

        // Reset button constraints
        NSLayoutConstraint.activate([
            resetButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -30),
            resetButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            resetButton.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 30),
            resetButton.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -30)
        ])
        print("Game element constraints activated.")
    }

    // --- Setup UI Creation & Management ---
    func createSetupUI() {
        print("Creating Setup UI")
        // --- Game Title Label ---
        gameTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        gameTitleLabel.text = "Gomoku"
        gameTitleLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold)
        gameTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        gameTitleLabel.textAlignment = .center
        gameTitleLabel.layer.shadowColor = UIColor.black.cgColor; gameTitleLabel.layer.shadowOffset = CGSize(width: 0, height: 2); gameTitleLabel.layer.shadowRadius = 4.0; gameTitleLabel.layer.shadowOpacity = 0.2; gameTitleLabel.layer.masksToBounds = false
        view.addSubview(gameTitleLabel)

        // Setup Title Label ("Choose Game Mode")
        setupTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        setupTitleLabel.text = "Choose Game Mode"; setupTitleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold); setupTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); setupTitleLabel.textAlignment = .center
        view.addSubview(setupTitleLabel)

        // Setup H vs AI Button
        startHvsAIButton.translatesAutoresizingMaskIntoConstraints = false
        startHvsAIButton.setTitle("Human vs AI (Easy)", for: .normal); startHvsAIButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold); startHvsAIButton.backgroundColor = UIColor(red: 0.8, green: 0.85, blue: 0.95, alpha: 1.0); startHvsAIButton.setTitleColor(.darkText, for: .normal); startHvsAIButton.layer.cornerRadius = 10; startHvsAIButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 25, bottom: 12, right: 25)
        startHvsAIButton.addTarget(self, action: #selector(didTapStartHvsAI), for: .touchUpInside)
        view.addSubview(startHvsAIButton)

        // Setup H vs H Button
        startHvsHButton.translatesAutoresizingMaskIntoConstraints = false
        startHvsHButton.setTitle("Human vs Human", for: .normal); startHvsHButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold); startHvsHButton.backgroundColor = UIColor(red: 0.85, green: 0.95, blue: 0.8, alpha: 1.0); startHvsHButton.setTitleColor(.darkText, for: .normal); startHvsHButton.layer.cornerRadius = 10; startHvsHButton.contentEdgeInsets = UIEdgeInsets(top: 12, left: 25, bottom: 12, right: 25)
        startHvsHButton.addTarget(self, action: #selector(didTapStartHvsH), for: .touchUpInside)
        view.addSubview(startHvsHButton)

        // Store references
        setupUIElements = [gameTitleLabel, setupTitleLabel, startHvsAIButton, startHvsHButton]
    }

    func setupSetupUIConstraints() {
        print("Setting up Setup UI constraints")
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Game Title
            gameTitleLabel.bottomAnchor.constraint(equalTo: setupTitleLabel.topAnchor, constant: -30),
            gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            gameTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20),
            gameTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),

            // "Choose Game Mode" Label
            setupTitleLabel.bottomAnchor.constraint(equalTo: startHvsAIButton.topAnchor, constant: -60),
            setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            setupTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20),
            setupTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),

            // H vs AI Button
            startHvsAIButton.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor, constant: 0), // Centered vertically
            startHvsAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            // H vs H Button
            startHvsHButton.topAnchor.constraint(equalTo: startHvsAIButton.bottomAnchor, constant: 20),
            startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            startHvsHButton.widthAnchor.constraint(equalTo: startHvsAIButton.widthAnchor)
        ])
    }

    // NEW Function to create and style the Main Menu button
    func createMainMenuButton() {
        print("Creating Main Menu Button")
        mainMenuButton.translatesAutoresizingMaskIntoConstraints = false
        mainMenuButton.setTitle("Main Menu", for: .normal)
        mainMenuButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .regular)
        mainMenuButton.setTitleColor(UIColor.systemGray, for: .normal)
        mainMenuButton.backgroundColor = .clear
        mainMenuButton.layer.cornerRadius = 6
        // Use configuration for padding if targeting iOS 15+
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain() // Use plain style for minimal appearance
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            mainMenuButton.configuration = config
        } else {
            mainMenuButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        }
        mainMenuButton.addTarget(self, action: #selector(didTapMainMenu), for: .touchUpInside)
        mainMenuButton.isHidden = true // Start hidden
        view.addSubview(mainMenuButton)
    }

    // NEW Function for Main Menu Button constraints
    func setupMainMenuButtonConstraints() {
        print("Setting up Main Menu Button constraints")
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            mainMenuButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 15),
            mainMenuButton.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -20)
        ])
    }


    func showSetupUI() {
        print("Showing Setup UI")
        currentGameState = .setup
        statusLabel.isHidden = true; boardView.isHidden = true; resetButton.isHidden = true; mainMenuButton.isHidden = true
        setupUIElements.forEach { $0.isHidden = false }
        boardView.gestureRecognizers?.forEach { boardView.removeGestureRecognizer($0) }
    }

    func showGameUI() {
        print("Showing Game UI")
        currentGameState = .playing
        statusLabel.isHidden = false; boardView.isHidden = false; resetButton.isHidden = false; mainMenuButton.isHidden = false
        setupUIElements.forEach { $0.isHidden = true }
        // Add tap recognizer only when game UI is shown
        // Ensure it's not added multiple times if showGameUI is called again
        if boardView.gestureRecognizers?.isEmpty ?? true {
             addTapGestureRecognizer()
        }
    }

    @objc func didTapStartHvsAI() { print("Start Human vs AI tapped"); startGame(mode: .humanVsAI) }
    @objc func didTapStartHvsH() { print("Start Human vs Human tapped"); startGame(mode: .humanVsHuman) }
    @objc func didTapMainMenu() { print("Main Menu button tapped"); showSetupUI() } // NEW Action

    func startGame(mode: GameMode) {
        print("Starting game mode: \(mode)")
        self.currentGameMode = mode
        showGameUI() // Transition UI first

        // Initialize / Reset game logic and state
        setupNewGame() // Resets board data, players, cellSize=0, lastDrawnBounds=0

        // CRITICAL: Trigger layout pass for the initial draw
        view.setNeedsLayout()
        // We rely on viewDidLayoutSubviews to draw after this layout pass completes
        // view.layoutIfNeeded() // Can potentially add back if initial draw is still problematic

        print("Game started.")
    }

    // --- Styling Functions ---
    func setupMainBackground() { /* ... unchanged ... */
        backgroundGradientLayer?.removeFromSuperlayer(); let gradient = CAGradientLayer(); gradient.frame = self.view.bounds; let topColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).cgColor; let bottomColor = UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1.0).cgColor; gradient.colors = [topColor, bottomColor]; gradient.startPoint = CGPoint(x: 0.5, y: 0.0); gradient.endPoint = CGPoint(x: 0.5, y: 1.0); self.view.layer.insertSublayer(gradient, at: 0); self.backgroundGradientLayer = gradient
    }
    // --- FIXED Reset Button Styling ---
    func styleResetButton() {
        guard let button = resetButton else { return }
        print("Styling Reset Button...")

        let buttonBackgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
        let buttonTextColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0)
        let buttonBorderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 0.8)

        // Use direct properties - avoid Configuration for now
        button.backgroundColor = buttonBackgroundColor
        button.setTitleColor(buttonTextColor, for: .normal)
        button.setTitleColor(buttonTextColor.withAlphaComponent(0.5), for: .highlighted) // Dim on highlight
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)

        // Layer Styling
        button.layer.cornerRadius = 8
        button.layer.borderWidth = 0.75
        button.layer.borderColor = buttonBorderColor.cgColor
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 2.5
        button.layer.shadowOpacity = 0.12
        button.layer.masksToBounds = false // For shadow

        // Padding using the older method (ignore deprecation warning for now)
         button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)

        print("Reset Button styling applied using direct properties.")
    }
    func styleStatusLabel() { /* ... unchanged ... */
         guard let label = statusLabel else { return }; label.font = UIFont.systemFont(ofSize: 22, weight: .medium); label.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0); label.textAlignment = .center; label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOffset = CGSize(width: 0, height: 1); label.layer.shadowRadius = 2.0; label.layer.shadowOpacity = 0.1; label.layer.masksToBounds = false
    }

    // --- Drawing Functions (Keep As Is) ---
    func drawProceduralWoodBackground() { /* ... unchanged ... */
         woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll()
         guard boardView.bounds.width > 0 && boardView.bounds.height > 0 else { print("Skipping wood background draw: boardView bounds not ready."); return }
         print("Drawing procedural wood background into bounds: \(boardView.bounds)"); let baseLayer = CALayer(); baseLayer.frame = boardView.bounds; baseLayer.backgroundColor = UIColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1.0).cgColor; baseLayer.cornerRadius = 10; baseLayer.masksToBounds = true
         boardView.layer.insertSublayer(baseLayer, at: 0); woodBackgroundLayers.append(baseLayer); let grainLayerCount = 35; let boardWidth = boardView.bounds.width; let boardHeight = boardView.bounds.height
         for _ in 0..<grainLayerCount { let grainLayer = CALayer(); let randomDarkness = CGFloat.random(in: -0.10...0.15); let baseRed: CGFloat = 0.65; let baseGreen: CGFloat = 0.50; let baseBlue: CGFloat = 0.35; let grainColor = UIColor(red: max(0.1, min(0.9, baseRed + randomDarkness)), green: max(0.1, min(0.9, baseGreen + randomDarkness)), blue: max(0.1, min(0.9, baseBlue + randomDarkness)), alpha: CGFloat.random(in: 0.1...0.35)); grainLayer.backgroundColor = grainColor.cgColor; let grainWidth = CGFloat.random(in: 1.5...4.0); let grainX = CGFloat.random(in: 0...(boardWidth - grainWidth)); grainLayer.frame = CGRect(x: grainX, y: 0, width: grainWidth, height: boardHeight); baseLayer.addSublayer(grainLayer) }
         let lightingGradient = CAGradientLayer(); lightingGradient.frame = boardView.bounds; lightingGradient.cornerRadius = baseLayer.cornerRadius; lightingGradient.type = .radial; lightingGradient.colors = [UIColor(white: 1.0, alpha: 0.15).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.15).cgColor]; lightingGradient.locations = [0.0, 0.6, 1.0]; baseLayer.addSublayer(lightingGradient); baseLayer.borderWidth = 2.0; baseLayer.borderColor = UIColor(white: 0.1, alpha: 0.8).cgColor
    }
    func drawBoard() { /* ... unchanged ... */
         boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }
         guard cellSize > 0 else { print("Skipping drawBoard: cellSize is 0"); return }
         guard woodBackgroundLayers.first != nil else { print("Cannot draw board: Wood background layer not found."); return }
         let boardDimension = cellSize * CGFloat(boardSize - 1); let gridLineColor = UIColor(white: 0.1, alpha: 0.65).cgColor; let gridLineWidth: CGFloat = 0.75
         for i in 0..<boardSize { let vLayer = CALayer(); let xPos = boardPadding + CGFloat(i) * cellSize; vLayer.frame = CGRect(x: xPos - (gridLineWidth / 2), y: boardPadding, width: gridLineWidth, height: boardDimension); vLayer.backgroundColor = gridLineColor; vLayer.name = "gridLine"; boardView.layer.addSublayer(vLayer); let hLayer = CALayer(); let yPos = boardPadding + CGFloat(i) * cellSize; hLayer.frame = CGRect(x: boardPadding, y: yPos - (gridLineWidth / 2), width: boardDimension, height: gridLineWidth); hLayer.backgroundColor = gridLineColor; hLayer.name = "gridLine"; boardView.layer.addSublayer(hLayer) }
         print("Board drawn with cell size: \(cellSize)")
    }
    func redrawPieces() { /* ... unchanged ... */
         guard cellSize > 0 else { print("Skipping redrawPieces: cellSize is 0"); return }
         boardView.subviews.forEach { $0.removeFromSuperview() }
         pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
         for r in 0..<boardSize { for c in 0..<boardSize { let cellState = board[r][c]; if cellState == .black || cellState == .white { drawPiece(atRow: r, col: c, player: (cellState == .black) ? .black : .white)}}}
    }
    func drawPiece(atRow row: Int, col: Int, player: Player) { /* ... unchanged ... */
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
          // No specific removal needed here if redrawPieces clears all first
          boardView.addSubview(pieceView)
          pieceViews[row][col] = pieceView
    }

    // --- Game Logic & Interaction ---
    // ADDED: Separate func to reset only non-UI state needed by viewDidLoad
    func setupNewGameVariablesOnly() {
        currentPlayer = .black; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); gameOver = false; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize)
    }
    func setupNewGame() { /* ... unchanged ... */
        print("setupNewGame called. Current Mode: \(currentGameMode)"); gameOver = false; currentPlayer = .black; statusLabel.text = "Black's Turn"; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize)
        boardView.subviews.forEach { $0.removeFromSuperview() }; boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll()
        pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); cellSize = 0; lastDrawnBoardBounds = .zero
        print("setupNewGame: Reset state, cellSize, and lastDrawnBoardBounds.")
        view.setNeedsLayout()
    }
    func calculateCellSize() -> CGFloat { /* ... unchanged ... */
         guard boardView.bounds.width > 0, boardView.bounds.height > 0 else { return 0 }
         let boardDimension = min(boardView.bounds.width, boardView.bounds.height) - (boardPadding * 2)
         guard boardSize > 1 else { return boardDimension }
         let size = boardDimension / CGFloat(boardSize - 1); return max(0, size)
    }
    func addTapGestureRecognizer() { /* ... unchanged ... */
         guard let currentBoardView = boardView else { print("FATAL ERROR: boardView outlet is NIL..."); return }; print("addTapGestureRecognizer attempting to add...")
         currentBoardView.gestureRecognizers?.forEach { currentBoardView.removeGestureRecognizer($0) }
         let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))); currentBoardView.addGestureRecognizer(tap); print("--> Tap Gesture Recognizer ADDED.")
    }
    @objc func handleTap(_ sender: UITapGestureRecognizer) { /* ... unchanged ... */
          guard currentGameState == .playing else { print("Tap ignored: Not in playing state."); return }; print("--- handleTap CALLED ---"); guard !gameOver, cellSize > 0 else { print("Guard FAILED: gameOver=\(gameOver), cellSize=\(cellSize)"); return }; guard !isAiTurn else { print("Tap ignored: It's AI's turn."); return }
          let location = sender.location(in: boardView); print("Tap location in view: \(location)")
          let playableWidth = boardView.bounds.width - 2 * boardPadding; let playableHeight = boardView.bounds.height - 2 * boardPadding; let tapArea = CGRect(x: boardPadding - cellSize*0.5, y: boardPadding - cellSize*0.5, width: playableWidth + cellSize, height: playableHeight + cellSize)
          guard tapArea.contains(location) else { print("Guard FAILED: Tap outside playable area."); return }
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
          guard currentGameState == .playing else { return }; let pieceState: CellState = (currentPlayer == .black) ? .black : .white; board[row][col] = pieceState
          drawPiece(atRow: row, col: col, player: currentPlayer)
          if checkForWin(playerState: pieceState, lastRow: row, lastCol: col) { gameOver = true; statusLabel.text = "\(currentPlayer == .black ? "Black" : "White") Wins!"; print("\(currentPlayer) Wins!"); view.isUserInteractionEnabled = true }
          else if isBoardFull() { gameOver = true; statusLabel.text = "Draw!"; print("Draw!"); view.isUserInteractionEnabled = true }
          else { switchPlayer() }
    }
    func switchPlayer() { /* ... unchanged ... */
         guard !gameOver else { return }; currentPlayer = (currentPlayer == .black) ? .white : .black; statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn"
         if isAiTurn { view.isUserInteractionEnabled = false; statusLabel.text = "Computer's Turn..."; print("Switching to AI turn..."); DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in guard let self = self else { return }; if !self.gameOver && self.isAiTurn { self.performAiTurn() } else { print("AI turn skipped (game over or state changed during delay)"); self.view.isUserInteractionEnabled = true } } }
         else { print("Switching to Human turn..."); view.isUserInteractionEnabled = true }
    }
    func performAiTurn() { /* ... unchanged ... */
         guard !gameOver else { view.isUserInteractionEnabled = true; return }; print("AI Turn: Performing AI move...")
         let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Turn: No empty cells left."); view.isUserInteractionEnabled = true; return }
         let humanPlayer: Player = (aiPlayer == .black) ? .white : .black
         for cell in emptyCells { if checkPotentialWin(player: aiPlayer, position: cell) { print("AI Turn: Found winning move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }
         for cell in emptyCells { if checkPotentialWin(player: humanPlayer, position: cell) { print("AI Turn: Found blocking move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }
         let adjacentCells = findAdjacentEmptyCells(); if let targetCell = adjacentCells.randomElement() { print("AI Turn: Playing random adjacent move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return }
         if let targetCell = emptyCells.randomElement() { print("AI Turn: Playing completely random move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return }
         print("AI Turn: Could not find any valid move."); view.isUserInteractionEnabled = true
    }
    func placeAiPieceAndEndTurn(at position: Position) { /* ... unchanged ... */ placePiece(atRow: position.row, col: position.col) }
    func checkPotentialWin(player: Player, position: Position) -> Bool { /* ... unchanged ... */
         var tempBoard = self.board; guard tempBoard[position.row][position.col] == .empty else { return false }; tempBoard[position.row][position.col] = (player == .black) ? .black : .white
         return checkForWinOnBoard(boardToCheck: tempBoard, playerState: tempBoard[position.row][position.col], lastRow: position.row, lastCol: position.col)
    }
    func checkForWinOnBoard(boardToCheck: [[CellState]], playerState: CellState, lastRow: Int, lastCol: Int) -> Bool { /* ... unchanged ... */
         guard playerState != .empty else { return false }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var count = 1
             for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } }
             for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } }
             if count >= 5 { return true } }; return false
    }
    func findEmptyCells() -> [Position] { /* ... unchanged ... */ var emptyPositions: [Position] = []; for r in 0..<boardSize { for c in 0..<boardSize { if board[r][c] == .empty { emptyPositions.append(Position(row: r, col: c)) } } }; return emptyPositions }
    func findAdjacentEmptyCells() -> [Position] { /* ... unchanged ... */ var adjacentEmpty = Set<Position>(); let directions = [(-1,-1), (-1,0), (-1,1), (0,-1), (0,1), (1,-1), (1,0), (1,1)]; for r in 0..<boardSize { for c in 0..<boardSize { if board[r][c] != .empty { for (dr, dc) in directions { let nr = r + dr; let nc = c + dc; if checkBounds(row: nr, col: nc) && board[nr][nc] == .empty { adjacentEmpty.insert(Position(row: nr, col: nc)) } } } } }; return Array(adjacentEmpty) }
    struct Position: Hashable { var row: Int; var col: Int }
    func isBoardFull() -> Bool { /* ... */ for row in board { if row.contains(.empty) { return false } }; return true }
    func checkForWin(playerState: CellState, lastRow: Int, lastCol: Int) -> Bool { return checkForWinOnBoard(boardToCheck: self.board, playerState: playerState, lastRow: lastRow, lastCol: lastCol) }
    func checkBounds(row: Int, col: Int) -> Bool { return row >= 0 && row < boardSize && col >= 0 && col < boardSize }


    // --- Reset Button Logic ---
    @IBAction func resetButtonTapped(_ sender: UIButton) { /* ... unchanged ... */
        print("Reset button DOWN"); UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: { sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }, completion: nil)
        if currentGameState == .playing { print("Resetting game..."); setupNewGame(); if !isAiTurn { view.isUserInteractionEnabled = true } } else { print("Reset tapped while in setup state - doing nothing.") }
        sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpInside); sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpOutside); sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchCancel)
    }
    @IBAction func resetButtonReleased(_ sender: UIButton) { /* ... unchanged ... */
          print("Reset button RELEASED"); UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: { sender.transform = .identity }, completion: { _ in sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside); sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside); sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)})
    }

} // End of ViewController class
