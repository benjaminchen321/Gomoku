import UIKit

class ViewController: UIViewController {

    // --- Outlets ---
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var boardView: UIView!
    @IBOutlet weak var resetButton: UIButton!
    
    // --- NEW: Properties for Adaptive Setup UI Constraints ---
    private var setupPortraitConstraints: [NSLayoutConstraint] = []
    private var setupLandscapeConstraints: [NSLayoutConstraint] = []
    private var currentSetupConstraints: [NSLayoutConstraint] = [] // Track active set

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

    // --- Game Setup State ---
    enum GameState { case setup, playing }
    enum GameMode { case humanVsHuman, humanVsAI }
    enum AIDifficulty { case easy, medium, hard}
    private var currentGameState: GameState = .setup
    private var currentGameMode: GameMode = .humanVsHuman

    // --- AI Control ---
    let aiPlayer: Player = .white
    private var selectedDifficulty: AIDifficulty = .easy
    var isAiTurn: Bool { currentGameMode == .humanVsAI && currentPlayer == aiPlayer }
    
    // --- NEW: Heuristic Scores for Hard AI ---
    // Assign weights to different patterns
    // Make winning infinitely good, blocking opponent win very high priority
    let scoreFiveInRow = 1000000
    let scoreOpenFour = 10000       // _XXXX_ or O_OOO_O
    let scoreBlockedFour = 5000    // XXXXX_ or O_OOOOX
    let scoreOpenThree = 500       // _XXX_ or O_OOO_
    let scoreBlockedThree = 100    // XXXX_ or O_OOOX
    let scoreOpenTwo = 10          // _XX_ or O_OO_
    let scoreBlockedTwo = 5        // XX_ or O_OX
    // Center preference can be added by giving small bonuses to center squares
    
    // --- Setup UI Elements ---
    private let gameTitleLabel = UILabel()      // NEW: Game Title
    private let setupTitleLabel = UILabel()
    private let startEasyAIButton = UIButton(type: .system)
    private let startMediumAIButton = UIButton(type: .system)
    private let startHardAIButton = UIButton(type: .system)
    private let startHvsHButton = UIButton(type: .system)
    private var setupUIElements: [UIView] = []

    // --- NEW: Main Menu Button ---
    private let mainMenuButton = UIButton(type: .system)
    
    // --- NEW: Game Over Overlay UI Elements ---
    private let gameOverOverlayView = UIView()
    private let gameOverStatusLabel = UILabel()
    private let playAgainButton = UIButton(type: .system)
    // We already have mainMenuButton, just need to add it to the overlay maybe?
    // Let's create a dedicated one for the overlay for clearer separation.
    private let overlayMainMenuButton = UIButton(type: .system)
    private var gameOverUIElements: [UIView] = [] // To manage visibility

    // --- Constraint Activation Flag ---
    private var constraintsActivated = false

    // --- Lifecycle Methods ---
    override func viewDidLoad() {
        super.viewDidLoad()
        print("viewDidLoad starting...")
        setupMainBackground()
        styleStatusLabel()
        boardView.backgroundColor = .clear
        styleResetButton()
        createMainMenuButton() // For top-left corner
        createSetupUI()
        createNewGameOverUI() // <<-- ADD THIS CALL
        setupNewGameVariablesOnly()
        showSetupUI() // Show setup initially
        print("viewDidLoad completed.")
    }

    // --- NEW: Function to Create Game Over UI ---
    func createNewGameOverUI() {
        print("Creating Game Over UI")

        // Overlay View Container
        gameOverOverlayView.translatesAutoresizingMaskIntoConstraints = false
        gameOverOverlayView.backgroundColor = UIColor.black.withAlphaComponent(0.65) // Semi-transparent dark
        gameOverOverlayView.layer.cornerRadius = 15
        gameOverOverlayView.isHidden = true // Start hidden
        view.addSubview(gameOverOverlayView) // Add to main view

        // Game Over Status Label (e.g., "White Wins!")
        gameOverStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        gameOverStatusLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold)
        gameOverStatusLabel.textColor = .white
        gameOverStatusLabel.textAlignment = .center
        gameOverStatusLabel.numberOfLines = 0 // Allow multiple lines if needed
        gameOverOverlayView.addSubview(gameOverStatusLabel) // Add TO OVERLAY

        // Play Again Button
        playAgainButton.translatesAutoresizingMaskIntoConstraints = false
        configureGameOverButton(playAgainButton, title: "Play Again", color: UIColor.systemGreen.withAlphaComponent(0.8))
        playAgainButton.addTarget(self, action: #selector(didTapPlayAgain), for: .touchUpInside)
        gameOverOverlayView.addSubview(playAgainButton) // Add TO OVERLAY

        // Main Menu Button (on Overlay)
        overlayMainMenuButton.translatesAutoresizingMaskIntoConstraints = false
        configureGameOverButton(overlayMainMenuButton, title: "Main Menu", color: UIColor.systemBlue.withAlphaComponent(0.8))
        overlayMainMenuButton.addTarget(self, action: #selector(didTapMainMenu), for: .touchUpInside) // Reuse existing action
        gameOverOverlayView.addSubview(overlayMainMenuButton) // Add TO OVERLAY

        // Store references
        gameOverUIElements = [gameOverOverlayView, gameOverStatusLabel, playAgainButton, overlayMainMenuButton]
    }

    // Helper to style overlay buttons
    func configureGameOverButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = color
            config.baseForegroundColor = .white
            config.cornerStyle = .medium
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
                return outgoing
            }
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
            button.configuration = config
        } else {
            // Fallback styling
            button.backgroundColor = color
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            button.layer.cornerRadius = 8
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        }
        // Add subtle shadow maybe
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
        button.layer.shadowRadius = 3
        button.layer.shadowOpacity = 0.3
        button.layer.masksToBounds = false
    }
    
    // --- NEW Helper to Activate/Deactivate Adaptive Constraints ---
    func applyAdaptiveSetupConstraints() {
        guard constraintsActivated else { return } // Ensure base constraints are set

        // Determine orientation based on view aspect ratio
        let isLandscape = view.bounds.width > view.bounds.height
        let targetConstraints = isLandscape ? setupLandscapeConstraints : setupPortraitConstraints

        // Check if the correct set is already active
        if currentSetupConstraints == targetConstraints && !currentSetupConstraints.isEmpty {
             // print("Correct setup constraints already active for \(isLandscape ? "Landscape" : "Portrait").")
             return // Do nothing if correct set is active
        }

        print("Applying setup constraints for \(isLandscape ? "Landscape" : "Portrait").")

        // Deactivate previously active setup constraints
        if !currentSetupConstraints.isEmpty {
            print("Deactivating \(currentSetupConstraints.count) old setup constraints.")
            NSLayoutConstraint.deactivate(currentSetupConstraints)
        }

        // Activate the new target constraints
        if !targetConstraints.isEmpty {
            print("Activating \(targetConstraints.count) new setup constraints.")
            NSLayoutConstraint.activate(targetConstraints)
            currentSetupConstraints = targetConstraints // Update tracked active set
        } else {
            print("Warning: Target constraint set is empty for \(isLandscape ? "Landscape" : "Portrait").")
            currentSetupConstraints = []
        }

        // Optional: Force layout update immediately after changing constraints
        // Might be needed if changes aren't reflecting instantly
        // self.view.layoutIfNeeded()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if !constraintsActivated {
            print("viewWillLayoutSubviews: Setting up ALL constraints for the first time.")
            setupConstraints() // Game Elements
            setupSetupUIConstraints() // Setup UI
            setupMainMenuButtonConstraints() // Menu Button
            setupGameOverUIConstraints() // <<-- ADD THIS CALL
            constraintsActivated = true
        }
        applyAdaptiveSetupConstraints()
    }

    // --- NEW: Constraints for Game Over UI ---
    func setupGameOverUIConstraints() {
        print("Setting up Game Over UI constraints")
        let safeArea = view.safeAreaLayoutGuide
        let buttonSpacing: CGFloat = 20

        NSLayoutConstraint.activate([
            // Overlay View (Centered, smaller than screen)
            gameOverOverlayView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            gameOverOverlayView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            gameOverOverlayView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: 0.7), // 70% of width
            gameOverOverlayView.heightAnchor.constraint(lessThanOrEqualTo: safeArea.heightAnchor, multiplier: 0.5), // Max 50% height

            // Game Over Status Label (Centered near top of overlay)
            gameOverStatusLabel.topAnchor.constraint(equalTo: gameOverOverlayView.topAnchor, constant: 30),
            gameOverStatusLabel.leadingAnchor.constraint(equalTo: gameOverOverlayView.leadingAnchor, constant: 20),
            gameOverStatusLabel.trailingAnchor.constraint(equalTo: gameOverOverlayView.trailingAnchor, constant: -20),
            gameOverStatusLabel.centerXAnchor.constraint(equalTo: gameOverOverlayView.centerXAnchor),

            // Play Again Button (Below Status)
            playAgainButton.topAnchor.constraint(equalTo: gameOverStatusLabel.bottomAnchor, constant: 30),
            playAgainButton.centerXAnchor.constraint(equalTo: gameOverOverlayView.centerXAnchor),

            // Main Menu Button (Below Play Again)
            overlayMainMenuButton.topAnchor.constraint(equalTo: playAgainButton.bottomAnchor, constant: buttonSpacing),
            overlayMainMenuButton.centerXAnchor.constraint(equalTo: gameOverOverlayView.centerXAnchor),
            overlayMainMenuButton.widthAnchor.constraint(equalTo: playAgainButton.widthAnchor), // Match width
            // Ensure bottom doesn't go beyond overlay
            overlayMainMenuButton.bottomAnchor.constraint(lessThanOrEqualTo: gameOverOverlayView.bottomAnchor, constant: -30)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        print("viewDidLayoutSubviews triggered. State: \(currentGameState)")
        
        // --- Debug Title Label ---
        print("Game Title Label - Frame: \(gameTitleLabel.frame), IsHidden: \(gameTitleLabel.isHidden), Superview: \(gameTitleLabel.superview == self.view)")

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

        // --- ADD Game Title Label FIRST ---
        gameTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        gameTitleLabel.text = "Gomoku"
        gameTitleLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold) // Large, bold
        gameTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
        gameTitleLabel.textAlignment = .center
        gameTitleLabel.layer.shadowColor = UIColor.black.cgColor; gameTitleLabel.layer.shadowOffset = CGSize(width: 0, height: 2); gameTitleLabel.layer.shadowRadius = 4.0; gameTitleLabel.layer.shadowOpacity = 0.2; gameTitleLabel.layer.masksToBounds = false
        view.addSubview(gameTitleLabel) // Add IMMEDIATELY
        // --- END ADD ---

        // Setup Title Label ("Choose Game Mode")
        setupTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        setupTitleLabel.text = "Choose Game Mode"; setupTitleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold); setupTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); setupTitleLabel.textAlignment = .center
        view.addSubview(setupTitleLabel)

        // Setup Buttons...
        startEasyAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startEasyAIButton, color: UIColor(red: 0.8, green: 0.95, blue: 0.85, alpha: 1.0)); startEasyAIButton.setTitle("vs AI (Easy)", for: .normal); startEasyAIButton.addTarget(self, action: #selector(didTapStartEasyAI), for: .touchUpInside); view.addSubview(startEasyAIButton)
        startMediumAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startMediumAIButton, color: UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1.0)); startMediumAIButton.setTitle("vs AI (Medium)", for: .normal); startMediumAIButton.addTarget(self, action: #selector(didTapStartMediumAI), for: .touchUpInside); view.addSubview(startMediumAIButton)
        startHardAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startHardAIButton, color: UIColor(red: 0.95, green: 0.8, blue: 0.8, alpha: 1.0)); startHardAIButton.setTitle("vs AI (Hard)", for: .normal); startHardAIButton.addTarget(self, action: #selector(didTapStartHardAI), for: .touchUpInside); view.addSubview(startHardAIButton)
        startHvsHButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startHvsHButton, color: UIColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 1.0)); startHvsHButton.setTitle("Human vs Human", for: .normal); startHvsHButton.addTarget(self, action: #selector(didTapStartHvsH), for: .touchUpInside); view.addSubview(startHvsHButton)

        // Store references including ALL elements
        setupUIElements = [gameTitleLabel, setupTitleLabel, startEasyAIButton, startMediumAIButton, startHardAIButton, startHvsHButton]
    }

    // Helper to configure common button styles
    func configureSetupButton(_ button: UIButton, color: UIColor) {
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = color
        button.setTitleColor(.darkText, for: .normal)
        button.layer.cornerRadius = 10
        // Use configuration for padding
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.baseBackgroundColor = color
            config.baseForegroundColor = .darkText
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 25, bottom: 12, trailing: 25)
            button.configuration = config
        } else {
             button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 25, bottom: 12, right: 25)
        }
    }

    // --- MODIFIED: Creates constraint sets but DOES NOT activate them ---
    func setupSetupUIConstraints() {
        print("Setting up Setup UI constraints (Creating Sets)")
        // Clear old arrays before repopulating
        setupPortraitConstraints.removeAll()
        setupLandscapeConstraints.removeAll()

        guard setupUIElements.count == 6 else { // Ensure all elements are created
            print("Error: Setup UI elements not fully created before constraint setup.")
            return
        }

        let safeArea = view.safeAreaLayoutGuide
        let buttonSpacing: CGFloat = 15
        let titleSpacing: CGFloat = 40

        // --- Portrait Constraints Definition ---
        setupPortraitConstraints = [
            // Game Title
            gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 80),
            gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            // "Choose Game Mode" Label
            setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: titleSpacing * 0.75),
            setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            // Buttons Stacked Vertically
            startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: titleSpacing),
            startEasyAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: buttonSpacing),
            startMediumAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),

            startHardAIButton.topAnchor.constraint(equalTo: startMediumAIButton.bottomAnchor, constant: buttonSpacing),
            startHardAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            startHardAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),

            startHvsHButton.topAnchor.constraint(equalTo: startHardAIButton.bottomAnchor, constant: buttonSpacing),
            startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor)
        ]

        // --- Landscape Constraints Definition (Example: 2x2 Grid for AI Buttons) ---
        setupLandscapeConstraints = [
            // Game Title (Maybe slightly higher in landscape)
            gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 30),
            gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            // "Choose Game Mode" Label (Below Title)
            setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: 20),
            setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            // Buttons in a 2x2 arrangement below "Choose..." label
            // Row 1: Easy | Medium
            startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: 30),
            startEasyAIButton.trailingAnchor.constraint(equalTo: safeArea.centerXAnchor, constant: -buttonSpacing / 2), // Left of center

            startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.topAnchor), // Align top
            startMediumAIButton.leadingAnchor.constraint(equalTo: safeArea.centerXAnchor, constant: buttonSpacing / 2), // Right of center
            startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor), // Match width

            // Row 2: Hard | HvsH
            startHardAIButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: buttonSpacing),
            startHardAIButton.trailingAnchor.constraint(equalTo: safeArea.centerXAnchor, constant: -buttonSpacing / 2), // Left of center
            startHardAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),

            startHvsHButton.topAnchor.constraint(equalTo: startHardAIButton.topAnchor), // Align top
            startHvsHButton.leadingAnchor.constraint(equalTo: safeArea.centerXAnchor, constant: buttonSpacing / 2), // Right of center
            startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor)
        ]
        print("Setup UI constraint sets created.")
    }

    func createMainMenuButton() {
        print("Creating Main Menu Button")
        mainMenuButton.translatesAutoresizingMaskIntoConstraints = false
        // Use configuration for best control
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain()
            config.title = "‹ Menu"
            // Ensure title alignment isn't causing issues if font size changes later
            config.titleAlignment = .leading
            config.baseForegroundColor = UIColor.systemBlue
            config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 10) // Add trailing padding
            mainMenuButton.configuration = config
        } else {
            // Fallback
            mainMenuButton.setTitle("‹ Menu", for: .normal)
            mainMenuButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
            mainMenuButton.setTitleColor(UIColor.systemBlue, for: .normal)
            mainMenuButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 10)
        }
        mainMenuButton.backgroundColor = .clear
        mainMenuButton.addTarget(self, action: #selector(didTapMainMenu), for: .touchUpInside)
        mainMenuButton.isHidden = true
        view.addSubview(mainMenuButton)
    }

    func setupMainMenuButtonConstraints() {
        print("Setting up Main Menu Button constraints")
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            // Pin to Top-Left Safe Area
            mainMenuButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 15), // Same top spacing
            mainMenuButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20), // Pin to left instead of right
            mainMenuButton.widthAnchor.constraint(lessThanOrEqualToConstant: 100)

            // Optional: Prevent overlap with statusLabel if statusLabel could be very wide
            // mainMenuButton.trailingAnchor.constraint(lessThanOrEqualTo: statusLabel.leadingAnchor, constant: -10)
        ])
    }

    func showSetupUI() {
        print("Showing Setup UI")
        currentGameState = .setup
        statusLabel.isHidden = true; boardView.isHidden = true; resetButton.isHidden = true; mainMenuButton.isHidden = true
        gameOverOverlayView.isHidden = true // <<-- Hide overlay too
        setupUIElements.forEach { $0.isHidden = false }
        gameTitleLabel.isHidden = false
        print("showSetupUI - Game Title isHidden: \(gameTitleLabel.isHidden)")
        boardView.gestureRecognizers?.forEach { boardView.removeGestureRecognizer($0) }
    }

    func showGameUI() {
        print("Showing Game UI")
        currentGameState = .playing
        statusLabel.isHidden = false; boardView.isHidden = false; resetButton.isHidden = false; mainMenuButton.isHidden = false
        gameOverOverlayView.isHidden = true // <<-- Hide overlay when game starts/restarts
        setupUIElements.forEach { $0.isHidden = true }
        gameTitleLabel.isHidden = true
        print("showGameUI - Game Title isHidden: \(gameTitleLabel.isHidden)")
        if boardView.gestureRecognizers?.isEmpty ?? true { addTapGestureRecognizer() }
    }

    // --- NEW: Function to show the Game Over overlay ---
    func showGameOverOverlay(message: String) {
        print("Showing Game Over Overlay: \(message)")
        gameOverStatusLabel.text = message // Set the winner text
        gameOverOverlayView.isHidden = false
        gameOverOverlayView.alpha = 0 // Start transparent
        view.bringSubviewToFront(gameOverOverlayView) // Ensure it's on top

        // Hide the normal reset button and main menu button during overlay
        resetButton.isHidden = true
        mainMenuButton.isHidden = true

        // Fade in animation
        UIView.animate(withDuration: 0.3) {
            self.gameOverOverlayView.alpha = 1.0
        }
        // Keep user interaction enabled for the overlay buttons
        view.isUserInteractionEnabled = true
    }

    // --- NEW: Action for "Play Again" button on overlay ---
    @objc func didTapPlayAgain() {
        print("Play Again tapped")
        hideGameOverOverlay()
        // Reset game with same mode/difficulty
        startGame(mode: currentGameMode, difficulty: selectedDifficulty)
    }

    // --- NEW: Function to hide the overlay ---
    func hideGameOverOverlay() {
        print("Hiding Game Over Overlay")
        // Could add fade out animation if desired
        gameOverOverlayView.isHidden = true
        // Re-show the normal in-game buttons IF the game is still in playing state
        // (In case Main Menu was tapped)
        if currentGameState == .playing {
             resetButton.isHidden = false
             mainMenuButton.isHidden = false
        }
    }

    // --- MODIFY: `didTapMainMenu` action to also hide overlay ---
    @objc func didTapMainMenu() {
        print("Main Menu button tapped")
        hideGameOverOverlay() // Hide overlay if visible
        showSetupUI() // Transition back to the setup screen
    }
    @objc func didTapStartEasyAI() { print("Start Easy AI tapped"); startGame(mode: .humanVsAI, difficulty: .easy) }
    @objc func didTapStartMediumAI() { print("Start Medium AI tapped"); startGame(mode: .humanVsAI, difficulty: .medium) }
    @objc func didTapStartHardAI() { print("Start Hard AI tapped"); startGame(mode: .humanVsAI, difficulty: .hard) }
    @objc func didTapStartHvsH() { print("Start Human vs Human tapped"); startGame(mode: .humanVsHuman, difficulty: .easy) } // Difficulty irrelevant for HvsH

    func startGame(mode: GameMode, difficulty: AIDifficulty) {
        print("Starting game mode: \(mode), Difficulty: \(difficulty)")
        self.currentGameMode = mode
        self.selectedDifficulty = (mode == .humanVsAI) ? difficulty : .easy // Store difficulty only for AI mode

        showGameUI() // Transition UI first
        setupNewGame() // Resets board data, players, cellSize=0, lastDrawnBounds=0
        view.setNeedsLayout() // Trigger layout pass for initial draw

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
// In placePiece function, ADD interaction enable on game over:
    func placePiece(atRow row: Int, col: Int) {
        guard currentGameState == .playing else { return }
        let pieceState: CellState = (currentPlayer == .black) ? .black : .white; board[row][col] = pieceState
        drawPiece(atRow: row, col: col, player: currentPlayer)

        let winner = checkForWinner(playerState: pieceState, lastRow: row, lastCol: col) // Use new helper

        if winner != nil || isBoardFull() {
            gameOver = true
            let message = (winner != nil) ? "\(winner == .black ? "Black" : "White") Wins!" : "Draw!"
            statusLabel.text = message // Update status label too
            print(message)
            showGameOverOverlay(message: message) // <<-- SHOW OVERLAY
        } else {
            switchPlayer()
        }
    }

    // --- NEW: Helper to determine winner (to avoid duplicate check) ---
     func checkForWinner(playerState: CellState, lastRow: Int, lastCol: Int) -> Player? {
         if checkForWinOnBoard(boardToCheck: self.board, playerState: playerState, lastRow: lastRow, lastCol: lastCol) {
             return (playerState == .black) ? .black : .white
         }
         return nil
     }
    
    // Modify switchPlayer interaction handling:
    func switchPlayer() {
        guard !gameOver else { return }

        let previousPlayer = currentPlayer // Store previous player
        currentPlayer = (currentPlayer == .black) ? .white : .black
        statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn"

        if isAiTurn { // Switching TO AI
            view.isUserInteractionEnabled = false // Disable for AI thinking
            statusLabel.text = "Computer (\(selectedDifficulty)) Turn..."
            print("Switching to AI (\(selectedDifficulty)) turn...")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
                guard let self = self else { return }
                // Check state hasn't changed unexpectedly
                if !self.gameOver && self.isAiTurn {
                     self.performAiTurn() // AI makes move, which calls placePiece, which calls switchPlayer again
                } else {
                     print("AI turn skipped (game over or state changed during delay)")
                     // If skipped, re-enable interaction because AI didn't move
                     self.view.isUserInteractionEnabled = true
                }
            }
        } else { // Switching TO Human (from AI or Human)
            print("Switching to Human turn...")
            // Enable interaction for the human player's turn
            view.isUserInteractionEnabled = true
        }
    }
    
    // --- AI Logic ---
    func performAiTurn() {
        guard !gameOver else { view.isUserInteractionEnabled = true; return }
        print("AI Turn (\(selectedDifficulty)): Performing move...")

        // --- Branch based on difficulty ---
        switch selectedDifficulty {
        case .easy:
            performEasyAiMove()
        case .medium:
            performMediumAiMove() // Now calls the implemented function
        case .hard:
            performHardAiMove()   // Still a placeholder -> falls back to easy
        }

        // Re-enable interaction AFTER the move function completes
        // This needs care as placeAiPieceAndEndTurn leads back to switchPlayer
        // Let's manage it more reliably in switchPlayer or placePiece completion
         DispatchQueue.main.async { // Ensure UI updates happen on main thread
             // Only re-enable if game isn't over and it's no longer AI's turn
             if !self.gameOver && !self.isAiTurn {
                  self.view.isUserInteractionEnabled = true
                  print("AI Turn (\(self.selectedDifficulty)): Re-enabled user interaction.")
             } else if self.gameOver {
                  self.view.isUserInteractionEnabled = true // Ensure enabled if game ended
                  print("AI Turn (\(self.selectedDifficulty)): Game Over, re-enabled user interaction.")
             }
             // If it's still somehow AI's turn (error), keep interaction disabled or handle error
         }
    }

    func performEasyAiMove() {
        let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Easy: No empty cells left."); return }
        let humanPlayer: Player = (aiPlayer == .black) ? .white : .black

        // Priority 1: Win
        for cell in emptyCells { if checkPotentialWin(player: aiPlayer, position: cell) { print("AI Easy: Found winning move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }
        // Priority 2: Block
        for cell in emptyCells { if checkPotentialWin(player: humanPlayer, position: cell) { print("AI Easy: Found blocking move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }

        // --- NEW Priority 3: Make Two ---
        var makeTwoMoves: [Position] = []
        for cell in emptyCells {
            if findMakeTwoMove(for: aiPlayer, potentialPosition: cell, on: self.board) != nil {
                makeTwoMoves.append(cell)
            }
        }
        if let makeTwoMove = makeTwoMoves.randomElement() {
            print("AI Easy: Found 'Make Two' move at \(makeTwoMove)")
            placeAiPieceAndEndTurn(at: makeTwoMove); return
        }

        // Fallback 1 (was 3): Adjacent Random
        let adjacentCells = findAdjacentEmptyCells(); if let targetCell = adjacentCells.randomElement() { print("AI Easy: Playing random adjacent move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return }
        // Fallback 2 (was 4): Random
        if let targetCell = emptyCells.randomElement() { print("AI Easy: Playing completely random move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return }
        print("AI Easy: Could not find any valid move.")
    }
    
    // --- NEW: Helper for Medium AI - Check for Open Three pattern ---
    // Checks if placing a piece at 'position' for 'player' would result in
    // creating or blocking an "Open Three" (_PPP_) along any axis.
    // Returns the position where the piece should be placed to achieve/block the Open Three.
    // NOTE: This is a simplified check, more robust checks exist.
    func findOpenThreeMove(for player: Player, potentialPosition: Position, on boardToCheck: [[CellState]]) -> Position? {
        let playerState: CellState = (player == .black) ? .black : .white
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)] // H, V, Diag\, Diag/

        for (dr, dc) in directions {
            // Check patterns like: E P P P E (where P is playerState) centered around potentialPosition
            // The potential move could be one of the 'E's.

            // Check E P P P [E] <- potentialPosition is the last E
            if checkPattern(pattern: [.empty, playerState, playerState, playerState, .empty],
                            startRow: potentialPosition.row - dr*4, startCol: potentialPosition.col - dc*4,
                            direction: (dr, dc), on: boardToCheck) {
                return potentialPosition // Placing here creates/blocks _PPP[E]
            }
            // Check [E] P P P E <- potentialPosition is the first E
            if checkPattern(pattern: [.empty, playerState, playerState, playerState, .empty],
                            startRow: potentialPosition.row, startCol: potentialPosition.col,
                            direction: (dr, dc), on: boardToCheck) {
                return potentialPosition // Placing here creates/blocks [E]PPPE
            }
             // Check P E P P E <- potentialPosition is the middle E (less common but possible block)
             if checkPattern(pattern: [playerState, .empty, playerState, playerState, .empty],
                             startRow: potentialPosition.row - dr, startCol: potentialPosition.col - dc,
                             direction: (dr, dc), on: boardToCheck) {
                 return potentialPosition
             }
              // Check P P E P E <- potentialPosition is the middle E
             if checkPattern(pattern: [playerState, playerState, .empty, playerState, .empty],
                             startRow: potentialPosition.row - dr*2, startCol: potentialPosition.col - dc*2,
                             direction: (dr, dc), on: boardToCheck) {
                 return potentialPosition
             }
              // Check P P P E E <- potentialPosition is the middle E
             if checkPattern(pattern: [playerState, playerState, playerState, .empty, .empty],
                             startRow: potentialPosition.row - dr*3, startCol: potentialPosition.col - dc*3,
                             direction: (dr, dc), on: boardToCheck) {
                 return potentialPosition
             }
        }
        return nil // No direct Open Three creation/block found at this position
    }
    
    // --- NEW: Helper for AI - Find moves that make two in a row ---
    // Checks if placing a piece at 'position' for 'player' creates a P P pattern
    // where one P is the new piece. Looks for _ P _ -> _ P P or P _ _ -> P P _ etc.
    func findMakeTwoMove(for player: Player, potentialPosition: Position, on boardToCheck: [[CellState]]) -> Position? {
         let playerState: CellState = (player == .black) ? .black : .white
         let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

        for (dr, dc) in directions {
            // Check pattern _ P [E] (potentialPosition is E)
            if checkPattern(pattern: [.empty, playerState, .empty],
                            startRow: potentialPosition.row - dr*2, startCol: potentialPosition.col - dc*2,
                            direction: (dr, dc), on: boardToCheck) {
                 return potentialPosition
            }
            // Check [E] P _ (potentialPosition is E)
             if checkPattern(pattern: [.empty, playerState, .empty],
                            startRow: potentialPosition.row, startCol: potentialPosition.col,
                            direction: (dr, dc), on: boardToCheck) {
                 return potentialPosition
            }
            // Check P _ [E] (potentialPosition is E)
            if checkPattern(pattern: [playerState, .empty, .empty],
                           startRow: potentialPosition.row - dr, startCol: potentialPosition.col - dc,
                           direction: (dr, dc), on: boardToCheck) {
                return potentialPosition
           }
           // Check [E] _ P (potentialPosition is E)
           if checkPattern(pattern: [.empty, .empty, playerState],
                           startRow: potentialPosition.row, startCol: potentialPosition.col,
                           direction: (dr, dc), on: boardToCheck) {
               return potentialPosition
           }
        }
        return nil
    }

    // Helper to check a specific pattern along a line
    func checkPattern(pattern: [CellState], startRow: Int, startCol: Int, direction: (dr: Int, dc: Int), on boardToCheck: [[CellState]]) -> Bool {
        for i in 0..<pattern.count {
            let r = startRow + direction.dr * i
            let c = startCol + direction.dc * i
            // Check bounds AND if the cell matches the expected state in the pattern
            if !checkBounds(row: r, col: c) || boardToCheck[r][c] != pattern[i] {
                return false // Pattern doesn't match
            }
        }
        return true // Pattern matched successfully
    }

    func performMediumAiMove() {
        let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Medium: No empty cells left."); return }
        let humanPlayer: Player = (aiPlayer == .black) ? .white : .black

        // 1. Win?
        for cell in emptyCells { if checkPotentialWin(player: aiPlayer, position: cell) { print("AI Medium: Found winning move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }
        // 2. Block Win?
        for cell in emptyCells { if checkPotentialWin(player: humanPlayer, position: cell) { print("AI Medium: Found blocking move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }
        // 3. Block Opponent's Open Three?
        var blockingOpenThreeMoves: [Position] = []; for cell in emptyCells { if findOpenThreeMove(for: humanPlayer, potentialPosition: cell, on: self.board) != nil { blockingOpenThreeMoves.append(cell) } }; if let blockMove = blockingOpenThreeMoves.randomElement() { print("AI Medium: Found blocking Open Three move at \(blockMove)"); placeAiPieceAndEndTurn(at: blockMove); return }
        // 4. Create Own Open Three?
        var creatingOpenThreeMoves: [Position] = []; for cell in emptyCells { var tempBoard = self.board; tempBoard[cell.row][cell.col] = (aiPlayer == .black) ? .black : .white; if findOpenThreeMove(for: aiPlayer, potentialPosition: cell, on: tempBoard) != nil { creatingOpenThreeMoves.append(cell) } }; if let createMove = creatingOpenThreeMoves.randomElement() { print("AI Medium: Found creating Open Three move at \(createMove)"); placeAiPieceAndEndTurn(at: createMove); return }

        // --- NEW Priority 5: Make Two ---
        var makeTwoMoves: [Position] = []
        for cell in emptyCells {
            if findMakeTwoMove(for: aiPlayer, potentialPosition: cell, on: self.board) != nil {
                makeTwoMoves.append(cell)
            }
        }
        if let makeTwoMove = makeTwoMoves.randomElement() {
            print("AI Medium: Found 'Make Two' move at \(makeTwoMove)")
            placeAiPieceAndEndTurn(at: makeTwoMove); return
        }

        // 6. Fallback to Easy AI logic (Adjacent / Random)
        print("AI Medium: No better move found. Falling back to Easy logic.")
        // Note: Easy AI now also includes the 'Make Two' check we just added,
        // making this fallback slightly smarter than before.
        performEasyAiMove() // Call the enhanced Easy AI logic

        // Removed direct random calls here as Easy handles the final fallbacks
        // let adjacentCells = findAdjacentEmptyCells(); if let targetCell = adjacentCells.randomElement() { ... }
        // if let targetCell = emptyCells.randomElement() { ... }
        // print("AI Medium: Could not find any valid move.") // Easy handles this message
    }
    
    func performHardAiMove() {
        // --- TEMPORARY FALLBACK ---
        print("AI Hard: Logic needs rework. Falling back to Medium logic.")
        performMediumAiMove() // Use Medium logic for now

        /* // --- Keep old heuristic code commented out for later debugging ---
        let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Hard: No empty cells left."); return }
        // ... (rest of the complex heuristic code) ...
        */
    }

    // placeAiPieceAndEndTurn remains the same
    func placeAiPieceAndEndTurn(at position: Position) {
        placePiece(atRow: position.row, col: position.col)
        // Interaction is enabled in the completion block of the performAiTurn caller (the DispatchQueue block)
    }
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
