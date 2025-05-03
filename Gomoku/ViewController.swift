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
    
    // --- ADD THESE MISSING PROPERTIES for Adaptive Setup UI ---
    private var setupPortraitConstraints: [NSLayoutConstraint] = []
    private var setupLandscapeConstraints: [NSLayoutConstraint] = []
    private var currentSetupConstraints: [NSLayoutConstraint] = [] // Track active set

    // --- AI Control ---
    // Renamed 'hard' to 'expert' but currently uses Medium logic
    enum AIDifficulty { case easy, medium, hard }
    let aiPlayer: Player = .white
    private var selectedDifficulty: AIDifficulty = .easy
    var isAiTurn: Bool { currentGameMode == .humanVsAI && currentPlayer == aiPlayer }

    // --- Layer References ---
    var backgroundGradientLayer: CAGradientLayer?
    var woodBackgroundLayers: [CALayer] = []
    private var lastDrawnBoardBounds: CGRect = .zero
    private var winningLineLayer: CAShapeLayer? // For win line

    // --- Game Setup State ---
    enum GameState { case setup, playing }
    enum GameMode { case humanVsHuman, humanVsAI }
    private var currentGameState: GameState = .setup
    private var currentGameMode: GameMode = .humanVsHuman

    // --- Setup UI Elements ---
    private let gameTitleLabel = UILabel()
    private let setupTitleLabel = UILabel()
    // Adjusted Button Naming for Clarity
    private let startEasyAIButton = UIButton(type: .system)
    private let startMediumAIButton = UIButton(type: .system) // Will trigger Standard AI
    // Removed Hard button UI element
    private let startHvsHButton = UIButton(type: .system)
    private var setupUIElements: [UIView] = []

    // --- Main Menu Button ---
    private let mainMenuButton = UIButton(type: .system)
    
    // --- Visual Polish Properties ---
    private var lastMovePosition: Position? = nil
    private var lastMoveIndicatorLayer: CALayer?
    private var turnIndicatorBorderLayer: CALayer?
    private var shakeAnimation: CABasicAnimation? // To create shake only once

    // --- Game Over Overlay UI Elements ---
    private let gameOverOverlayView = UIVisualEffectView()
    private let gameOverStatusLabel = UILabel()
    private let playAgainButton = UIButton(type: .system)
    private let overlayMainMenuButton = UIButton(type: .system)
    private var gameOverUIElements: [UIView] = []

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
        createMainMenuButton()
        createSetupUI()
        createNewGameOverUI()
        setupTurnIndicatorBorder()
        setupNewGameVariablesOnly()
        showSetupUI()
        print("viewDidLoad completed.")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if !constraintsActivated {
            print("viewWillLayoutSubviews: Setting up ALL constraints for the first time.")
            setupConstraints() // Game Elements
            setupSetupUIConstraints() // Setup UI (Creates Sets) -> Now includes Title fix
            setupMainMenuButtonConstraints() // Menu Button
            setupGameOverUIConstraints() // Game Over Overlay
            constraintsActivated = true
        }
         // Apply correct adaptive constraints for setup UI based on current size
         applyAdaptiveSetupConstraints()
    }
    
    // Called once from viewDidLoad after constraints are set
    func setupTurnIndicatorBorder() {
        guard turnIndicatorBorderLayer == nil else { return } // Create only once

        let borderLayer = CALayer()
        borderLayer.borderWidth = 3.0 // Thickness of indicator
        borderLayer.cornerRadius = boardView.layer.cornerRadius + 4 // Match board corner radius + padding
        borderLayer.masksToBounds = true // Needed if using background color instead of border
        borderLayer.borderColor = UIColor.clear.cgColor // Start clear
        // Position needs to be updated in viewDidLayoutSubviews
        boardView.layer.addSublayer(borderLayer) // Add as sublayer of boardView
        self.turnIndicatorBorderLayer = borderLayer
        print("Turn indicator border layer created.")
    }

    // --- NEW: Function to Update Turn Indicator Appearance ---
    func updateTurnIndicator() {
        guard let borderLayer = turnIndicatorBorderLayer else { return }

        let targetColor: UIColor
        if gameOver {
            targetColor = .clear // Hide border when game is over
        } else {
            targetColor = (currentPlayer == .black) ? .black : .white
        }

        // Animate border color change
        let colorAnimation = CABasicAnimation(keyPath: "borderColor")
        // Ensure we animate from the current presentation layer's color if mid-animation
        colorAnimation.fromValue = borderLayer.presentation()?.borderColor ?? borderLayer.borderColor
        colorAnimation.toValue = targetColor.withAlphaComponent(0.6).cgColor // Semi-transparent
        colorAnimation.duration = 0.3
        colorAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Update the model layer immediately
        borderLayer.borderColor = targetColor.withAlphaComponent(0.6).cgColor
        // Add the animation
        borderLayer.add(colorAnimation, forKey: "borderColorChange")

        print("Updated turn indicator color for \(currentPlayer)")
    }


    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        print("viewDidLayoutSubviews triggered. State: \(currentGameState)")
        self.backgroundGradientLayer?.frame = self.view.bounds

        // Debug Title Frame
        if currentGameState == .setup {
            print("Setup State - Game Title Label - Frame: \(gameTitleLabel.frame), IsHidden: \(gameTitleLabel.isHidden)")
        }

        guard currentGameState == .playing else {
            print("viewDidLayoutSubviews: Not in playing state, skipping board draw.")
            return
        }
        
        // Update turn indicator frame to match boardView bounds + padding
        if let borderLayer = turnIndicatorBorderLayer {
            borderLayer.frame = boardView.bounds.insetBy(dx: -4, dy: -4) // Slightly outside board bounds
            borderLayer.cornerRadius = boardView.layer.cornerRadius + 4
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
        
        // --- IMPORTANT: Ensure initial turn indicator update ---
        if currentGameState == .playing && !gameOver && turnIndicatorBorderLayer?.borderColor == UIColor.clear.cgColor {
             // If game started but indicator is still clear, update it
             updateTurnIndicator()
        }
    }

    // --- Constraint Setup (YOUR WORKING VERSION for game elements) ---
    func setupConstraints() {
        guard let statusLabel = statusLabel, let boardView = boardView, let resetButton = resetButton else { print("Error: Outlets not connected for game elements!"); return }
        // Ensure constraints are only added once
        guard !self.view.constraints.contains(where: { $0.firstItem === boardView || $0.secondItem === boardView }) else { print("Game element constraints already seem to exist."); return }

        print("Setting up game element constraints..."); statusLabel.translatesAutoresizingMaskIntoConstraints = false; boardView.translatesAutoresizingMaskIntoConstraints = false; resetButton.translatesAutoresizingMaskIntoConstraints = false
        let safeArea = view.safeAreaLayoutGuide
        let centerXConstraint = boardView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor); let centerYConstraint = boardView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        let aspectRatioConstraint = boardView.heightAnchor.constraint(equalTo: boardView.widthAnchor, multiplier: 1.0); aspectRatioConstraint.priority = .required; let leadingConstraint = boardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20)
        let trailingConstraint = boardView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20); let topConstraint = boardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 80)
        let bottomConstraint = boardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -80); let widthConstraint = boardView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -40); widthConstraint.priority = .defaultHigh
        let heightConstraint = boardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -160); heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([centerXConstraint, centerYConstraint, aspectRatioConstraint, leadingConstraint, trailingConstraint, topConstraint, bottomConstraint, widthConstraint, heightConstraint])
        NSLayoutConstraint.activate([statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20), statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20), statusLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)])
        NSLayoutConstraint.activate([resetButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -30), resetButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), resetButton.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 30), resetButton.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -30)])
        print("Game element constraints activated.")
    }

    // --- Setup UI Creation & Management ---
    func createSetupUI() {
        print("Creating Setup UI")
        // Game Title Label FIRST
        gameTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        gameTitleLabel.text = "Gomoku"; gameTitleLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold); gameTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); gameTitleLabel.textAlignment = .center
        gameTitleLabel.layer.shadowColor = UIColor.black.cgColor; gameTitleLabel.layer.shadowOffset = CGSize(width: 0, height: 2); gameTitleLabel.layer.shadowRadius = 4.0; gameTitleLabel.layer.shadowOpacity = 0.2; gameTitleLabel.layer.masksToBounds = false
        view.addSubview(gameTitleLabel)

        // "Choose Game Mode" Label
        setupTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        setupTitleLabel.text = "Choose Game Mode"; setupTitleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold); setupTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); setupTitleLabel.textAlignment = .center
        view.addSubview(setupTitleLabel)

        // Buttons (No Hard Button)
        startEasyAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startEasyAIButton, color: UIColor(red: 0.8, green: 0.95, blue: 0.85, alpha: 1.0)); startEasyAIButton.setTitle("vs AI (Easy)", for: .normal); startEasyAIButton.addTarget(self, action: #selector(didTapStartEasyAI), for: .touchUpInside); view.addSubview(startEasyAIButton)
        startMediumAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startMediumAIButton, color: UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1.0)); startMediumAIButton.setTitle("vs AI (Medium)", for: .normal); startMediumAIButton.addTarget(self, action: #selector(didTapStartMediumAI), for: .touchUpInside); view.addSubview(startMediumAIButton)
        startHvsHButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startHvsHButton, color: UIColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 1.0)); startHvsHButton.setTitle("Human vs Human", for: .normal); startHvsHButton.addTarget(self, action: #selector(didTapStartHvsH), for: .touchUpInside); view.addSubview(startHvsHButton)

        // Update stored elements array
        setupUIElements = [gameTitleLabel, setupTitleLabel, startEasyAIButton, startMediumAIButton, /* REMOVED startHardAIButton, */ startHvsHButton]
    }
    // Helper to configure common button styles
    func configureSetupButton(_ button: UIButton, color: UIColor) {
         button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold); button.backgroundColor = color; button.setTitleColor(.darkText, for: .normal); button.layer.cornerRadius = 10
         if #available(iOS 15.0, *) { var config = UIButton.Configuration.filled(); config.baseBackgroundColor = color; config.baseForegroundColor = .darkText; config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 25, bottom: 12, trailing: 25); button.configuration = config } else { button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 25, bottom: 12, right: 25) }
    }

    // --- FIXED Setup UI Constraints ---
    func setupSetupUIConstraints() {
        print("Setting up Setup UI constraints (Creating Sets)")
        setupPortraitConstraints.removeAll(); setupLandscapeConstraints.removeAll()
        guard setupUIElements.count == 5 else { // Should be 5 elements now
            print("Error: Setup UI elements count mismatch (\(setupUIElements.count)). Expected 5."); return
        }
        let safeArea = view.safeAreaLayoutGuide; let buttonSpacing: CGFloat = 15; let titleSpacing: CGFloat = 40

        // Portrait Constraints Definition
        setupPortraitConstraints = [
            gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 80), // Fixed position
            gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            gameTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), // Added back
            gameTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),  // Added back

            setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: titleSpacing * 0.5),
            setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            setupTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20),
            setupTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),

            startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: titleSpacing),
            startEasyAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: buttonSpacing),
            startMediumAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),

            // H vs H Button now below Medium
            startHvsHButton.topAnchor.constraint(equalTo: startMediumAIButton.bottomAnchor, constant: buttonSpacing),
            startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor)
        ]

        // Landscape Constraints Definition (Example: 2x2 Grid)
        setupLandscapeConstraints = [
            gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 30),
            gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            gameTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), // Added back
            gameTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20),  // Added back


            setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: 20),
            setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),

            // Row 1: Easy | Medium
            startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: 30),
            startEasyAIButton.trailingAnchor.constraint(equalTo: safeArea.centerXAnchor, constant: -buttonSpacing / 2),

            startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.topAnchor),
            startMediumAIButton.leadingAnchor.constraint(equalTo: safeArea.centerXAnchor, constant: buttonSpacing / 2),
            startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor),

            // Row 2: HvsH (No Hard button) - Position below Easy/Medium row, centered? Or just below Easy?
            startHvsHButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: buttonSpacing), // Below first row
            startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), // Center it
            startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor) // Maybe match width
        ]
        print("Setup UI constraint sets created.")
    }

    // NEW Helper to Activate/Deactivate Adaptive Constraints
    func applyAdaptiveSetupConstraints() {
        // ... (applyAdaptiveSetupConstraints function unchanged from previous version) ...
         guard constraintsActivated else { return }
         let isLandscape = view.bounds.width > view.bounds.height
         let targetConstraints = isLandscape ? setupLandscapeConstraints : setupPortraitConstraints
         if currentSetupConstraints == targetConstraints && !currentSetupConstraints.isEmpty { return }
         print("Applying setup constraints for \(isLandscape ? "Landscape" : "Portrait").")
         if !currentSetupConstraints.isEmpty { print("Deactivating \(currentSetupConstraints.count) old setup constraints."); NSLayoutConstraint.deactivate(currentSetupConstraints) }
         if !targetConstraints.isEmpty { print("Activating \(targetConstraints.count) new setup constraints."); NSLayoutConstraint.activate(targetConstraints); currentSetupConstraints = targetConstraints }
         else { print("Warning: Target constraint set is empty for \(isLandscape ? "Landscape" : "Portrait")."); currentSetupConstraints = [] }
    }

    // Create/Constraint Main Menu Button (Unchanged)
    func createMainMenuButton() { /* ... */
        print("Creating Main Menu Button"); mainMenuButton.translatesAutoresizingMaskIntoConstraints = false; if #available(iOS 15.0, *) { var config = UIButton.Configuration.plain(); config.title = "‹ Menu"; config.titleAlignment = .leading; config.baseForegroundColor = UIColor.systemBlue; config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 10); mainMenuButton.configuration = config } else { mainMenuButton.setTitle("‹ Menu", for: .normal); mainMenuButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium); mainMenuButton.setTitleColor(UIColor.systemBlue, for: .normal); mainMenuButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 10) }; mainMenuButton.backgroundColor = .clear; mainMenuButton.addTarget(self, action: #selector(didTapMainMenu), for: .touchUpInside); mainMenuButton.isHidden = true; view.addSubview(mainMenuButton)
    }
    func setupMainMenuButtonConstraints() { /* ... */
        print("Setting up Main Menu Button constraints"); let safeArea = view.safeAreaLayoutGuide; NSLayoutConstraint.activate([ mainMenuButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 15), mainMenuButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20) /*, mainMenuButton.widthAnchor.constraint(lessThanOrEqualToConstant: 100) */ ])
    }

    // Create/Constraint Game Over UI (Unchanged)
    func createNewGameOverUI() { /* ... */
         print("Creating Game Over UI with Blur"); gameOverOverlayView.translatesAutoresizingMaskIntoConstraints = false; gameOverOverlayView.effect = UIBlurEffect(style: .systemMaterialDark); gameOverOverlayView.layer.cornerRadius = 15; gameOverOverlayView.layer.masksToBounds = true; gameOverOverlayView.isHidden = true
         gameOverOverlayView.contentView.addSubview(gameOverStatusLabel); gameOverOverlayView.contentView.addSubview(playAgainButton); gameOverOverlayView.contentView.addSubview(overlayMainMenuButton); view.addSubview(gameOverOverlayView)
         gameOverStatusLabel.translatesAutoresizingMaskIntoConstraints = false; gameOverStatusLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold); gameOverStatusLabel.textColor = .white; gameOverStatusLabel.textAlignment = .center; gameOverStatusLabel.numberOfLines = 0
         playAgainButton.translatesAutoresizingMaskIntoConstraints = false; configureGameOverButton(playAgainButton, title: "Play Again", color: UIColor.systemGreen.withAlphaComponent(0.8)); playAgainButton.addTarget(self, action: #selector(didTapPlayAgain), for: .touchUpInside)
         overlayMainMenuButton.translatesAutoresizingMaskIntoConstraints = false; configureGameOverButton(overlayMainMenuButton, title: "Main Menu", color: UIColor.systemBlue.withAlphaComponent(0.8)); overlayMainMenuButton.addTarget(self, action: #selector(didTapMainMenu), for: .touchUpInside)
         gameOverUIElements = [gameOverOverlayView, gameOverStatusLabel, playAgainButton, overlayMainMenuButton]
    }
    func configureGameOverButton(_ button: UIButton, title: String, color: UIColor) { /* ... */
        button.setTitle(title, for: .normal); if #available(iOS 15.0, *) { var config = UIButton.Configuration.filled(); config.baseBackgroundColor = color; config.baseForegroundColor = .white; config.cornerStyle = .medium; config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in var outgoing = incoming; outgoing.font = UIFont.systemFont(ofSize: 18, weight: .semibold); return outgoing }; config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20); button.configuration = config } else { button.backgroundColor = color; button.setTitleColor(.white, for: .normal); button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold); button.layer.cornerRadius = 8; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20) }; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 3; button.layer.shadowOpacity = 0.3; button.layer.masksToBounds = false
    }
    func setupGameOverUIConstraints() { /* ... */
         print("Setting up Game Over UI constraints"); let safeArea = view.safeAreaLayoutGuide; let buttonSpacing: CGFloat = 20; let overlayContentView = gameOverOverlayView.contentView
         NSLayoutConstraint.activate([ gameOverOverlayView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), gameOverOverlayView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor), gameOverOverlayView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: 0.7), gameOverOverlayView.heightAnchor.constraint(lessThanOrEqualTo: safeArea.heightAnchor, multiplier: 0.5), gameOverStatusLabel.topAnchor.constraint(equalTo: overlayContentView.topAnchor, constant: 30), gameOverStatusLabel.leadingAnchor.constraint(equalTo: overlayContentView.leadingAnchor, constant: 20), gameOverStatusLabel.trailingAnchor.constraint(equalTo: overlayContentView.trailingAnchor, constant: -20), playAgainButton.topAnchor.constraint(equalTo: gameOverStatusLabel.bottomAnchor, constant: 30), playAgainButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor), overlayMainMenuButton.topAnchor.constraint(equalTo: playAgainButton.bottomAnchor, constant: buttonSpacing), overlayMainMenuButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor), overlayMainMenuButton.widthAnchor.constraint(equalTo: playAgainButton.widthAnchor), overlayMainMenuButton.bottomAnchor.constraint(lessThanOrEqualTo: overlayContentView.bottomAnchor, constant: -30) ])
    }

    // Visibility Functions (Unchanged - Already handle title visibility)
    func showSetupUI() { /* ... */
         print("Showing Setup UI"); currentGameState = .setup; statusLabel.isHidden = true; boardView.isHidden = true; resetButton.isHidden = true; mainMenuButton.isHidden = true; gameOverOverlayView.isHidden = true; setupUIElements.forEach { $0.isHidden = false }; gameTitleLabel.isHidden = false; print("showSetupUI - Game Title isHidden: \(gameTitleLabel.isHidden)"); boardView.gestureRecognizers?.forEach { boardView.removeGestureRecognizer($0) }
    }
    func showGameUI() { /* ... */
        print("Showing Game UI"); currentGameState = .playing; statusLabel.isHidden = false; boardView.isHidden = false; resetButton.isHidden = false; mainMenuButton.isHidden = false; gameOverOverlayView.isHidden = true; setupUIElements.forEach { $0.isHidden = true }; gameTitleLabel.isHidden = true; print("showGameUI - Game Title isHidden: \(gameTitleLabel.isHidden)"); if boardView.gestureRecognizers?.isEmpty ?? true { addTapGestureRecognizer() }
    }
    func showGameOverOverlay(message: String) { /* ... */
        print("Showing Game Over Overlay: \(message)"); gameOverStatusLabel.text = message; gameOverOverlayView.isHidden = false; gameOverOverlayView.alpha = 0; gameOverOverlayView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1); view.bringSubviewToFront(gameOverOverlayView); resetButton.isHidden = true; mainMenuButton.isHidden = true; UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: .curveEaseOut, animations: { self.gameOverOverlayView.alpha = 1.0; self.gameOverOverlayView.transform = .identity }, completion: nil); view.isUserInteractionEnabled = true
    }
    func hideGameOverOverlay() { /* ... */
         print("Hiding Game Over Overlay"); UIView.animate(withDuration: 0.2, animations: { self.gameOverOverlayView.alpha = 0.0; self.gameOverOverlayView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9) }) { _ in self.gameOverOverlayView.isHidden = true; self.gameOverOverlayView.transform = .identity; if self.currentGameState == .playing { self.resetButton.isHidden = false; self.mainMenuButton.isHidden = false } }
    }

    // Button Actions (Unchanged)
    @objc func didTapPlayAgain() { print("Play Again tapped"); hideGameOverOverlay(); startGame(mode: currentGameMode, difficulty: selectedDifficulty) }
    @objc func didTapMainMenu() { print("Main Menu button tapped"); hideGameOverOverlay(); showSetupUI() }
    @objc func didTapStartEasyAI() { print("Start Easy AI tapped"); startGame(mode: .humanVsAI, difficulty: .easy) }
    @objc func didTapStartMediumAI() { print("Start Medium AI tapped"); startGame(mode: .humanVsAI, difficulty: .medium) } // Medium button now triggers medium logic
    // REMOVED: @objc func didTapStartHardAI()
    @objc func didTapStartHvsH() { print("Start Human vs Human tapped"); startGame(mode: .humanVsHuman, difficulty: .easy) }
    func startGame(mode: GameMode, difficulty: AIDifficulty) { /* ... */ print("Starting game mode: \(mode), Difficulty: \(difficulty)"); self.currentGameMode = mode; self.selectedDifficulty = (mode == .humanVsAI) ? difficulty : .easy; showGameUI(); setupNewGame(); view.setNeedsLayout(); print("Game started.") }

    // --- Styling Functions (Unchanged, including FIXED styleResetButton) ---
    func setupMainBackground() { /* ... */ backgroundGradientLayer?.removeFromSuperlayer(); let gradient = CAGradientLayer(); gradient.frame = self.view.bounds; let topColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).cgColor; let bottomColor = UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1.0).cgColor; gradient.colors = [topColor, bottomColor]; gradient.startPoint = CGPoint(x: 0.5, y: 0.0); gradient.endPoint = CGPoint(x: 0.5, y: 1.0); self.view.layer.insertSublayer(gradient, at: 0); self.backgroundGradientLayer = gradient }
    func styleResetButton() { /* ... */ guard let button = resetButton else { return }; print("Styling Reset Button..."); let bgColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0); let textColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0); let borderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 0.8); button.backgroundColor = bgColor; button.setTitleColor(textColor, for: .normal); button.setTitleColor(textColor.withAlphaComponent(0.5), for: .highlighted); button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold); button.layer.cornerRadius = 8; button.layer.borderWidth = 0.75; button.layer.borderColor = borderColor.cgColor; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20); print("Reset Button styling applied using direct properties.") }
    func styleStatusLabel() { /* ... */ guard let label = statusLabel else { return }; label.font = UIFont.systemFont(ofSize: 22, weight: .medium); label.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0); label.textAlignment = .center; label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOffset = CGSize(width: 0, height: 1); label.layer.shadowRadius = 2.0; label.layer.shadowOpacity = 0.1; label.layer.masksToBounds = false }

    // --- Drawing Functions (Unchanged) ---
    func drawProceduralWoodBackground() { /* ... */ woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll(); guard boardView.bounds.width > 0 && boardView.bounds.height > 0 else { print("Skipping wood background draw: boardView bounds not ready."); return }; print("Drawing procedural wood background into bounds: \(boardView.bounds)"); let baseLayer = CALayer(); baseLayer.frame = boardView.bounds; baseLayer.backgroundColor = UIColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1.0).cgColor; baseLayer.cornerRadius = 10; baseLayer.masksToBounds = true; boardView.layer.insertSublayer(baseLayer, at: 0); woodBackgroundLayers.append(baseLayer); let grainLayerCount = 35; let boardWidth = boardView.bounds.width; let boardHeight = boardView.bounds.height; for _ in 0..<grainLayerCount { let grainLayer = CALayer(); let randomDarkness = CGFloat.random(in: -0.10...0.15); let baseRed: CGFloat = 0.65; let baseGreen: CGFloat = 0.50; let baseBlue: CGFloat = 0.35; let grainColor = UIColor(red: max(0.1, min(0.9, baseRed + randomDarkness)), green: max(0.1, min(0.9, baseGreen + randomDarkness)), blue: max(0.1, min(0.9, baseBlue + randomDarkness)), alpha: CGFloat.random(in: 0.1...0.35)); grainLayer.backgroundColor = grainColor.cgColor; let grainWidth = CGFloat.random(in: 1.5...4.0); let grainX = CGFloat.random(in: 0...(boardWidth - grainWidth)); grainLayer.frame = CGRect(x: grainX, y: 0, width: grainWidth, height: boardHeight); baseLayer.addSublayer(grainLayer) }; let lightingGradient = CAGradientLayer(); lightingGradient.frame = boardView.bounds; lightingGradient.cornerRadius = baseLayer.cornerRadius; lightingGradient.type = .radial; lightingGradient.colors = [UIColor(white: 1.0, alpha: 0.15).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.15).cgColor]; lightingGradient.locations = [0.0, 0.6, 1.0]; baseLayer.addSublayer(lightingGradient); baseLayer.borderWidth = 2.0; baseLayer.borderColor = UIColor(white: 0.1, alpha: 0.8).cgColor }
    func drawBoard() { /* ... */ boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }; guard cellSize > 0 else { print("Skipping drawBoard: cellSize is 0"); return }; guard woodBackgroundLayers.first != nil else { print("Cannot draw board: Wood background layer not found."); return }; let boardDimension = cellSize * CGFloat(boardSize - 1); let gridLineColor = UIColor(white: 0.1, alpha: 0.65).cgColor; let gridLineWidth: CGFloat = 0.75; for i in 0..<boardSize { let vLayer = CALayer(); let xPos = boardPadding + CGFloat(i) * cellSize; vLayer.frame = CGRect(x: xPos - (gridLineWidth / 2), y: boardPadding, width: gridLineWidth, height: boardDimension); vLayer.backgroundColor = gridLineColor; vLayer.name = "gridLine"; boardView.layer.addSublayer(vLayer); let hLayer = CALayer(); let yPos = boardPadding + CGFloat(i) * cellSize; hLayer.frame = CGRect(x: boardPadding, y: yPos - (gridLineWidth / 2), width: boardDimension, height: gridLineWidth); hLayer.backgroundColor = gridLineColor; hLayer.name = "gridLine"; boardView.layer.addSublayer(hLayer) }; print("Board drawn with cell size: \(cellSize)") }
    func redrawPieces() { /* ... */ guard cellSize > 0 else { print("Skipping redrawPieces: cellSize is 0"); return }; boardView.subviews.forEach { $0.removeFromSuperview() }; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); for r in 0..<boardSize { for c in 0..<boardSize { let cellState = board[r][c]; if cellState == .black || cellState == .white { drawPiece(atRow: r, col: c, player: (cellState == .black) ? .black : .white)}}} }
    func drawPiece(atRow row: Int, col: Int, player: Player) {
        guard cellSize > 0 else { return }
        let pieceSize = cellSize * 0.85; let x = boardPadding + CGFloat(col) * cellSize - (pieceSize / 2); let y = boardPadding + CGFloat(row) * cellSize - (pieceSize / 2); let pieceFrame = CGRect(x: x, y: y, width: pieceSize, height: pieceSize)
        let pieceView = UIView(frame: pieceFrame); pieceView.backgroundColor = .clear

        // --- Stone Visual Refinement (Slightly Sharper Highlight) ---
        let gradientLayer = CAGradientLayer(); gradientLayer.frame = pieceView.bounds; gradientLayer.cornerRadius = pieceSize / 2; gradientLayer.type = .radial
        let lightColor: UIColor; let darkColor: UIColor; let highlightColor: UIColor
        if player == .black {
            highlightColor = UIColor(white: 0.5, alpha: 1.0) // Brighter highlight for black
            lightColor = UIColor(white: 0.3, alpha: 1.0)
            darkColor = UIColor(white: 0.05, alpha: 1.0)
        } else {
            highlightColor = UIColor(white: 1.0, alpha: 1.0) // Pure white highlight
            lightColor = UIColor(white: 0.95, alpha: 1.0)
            darkColor = UIColor(white: 0.75, alpha: 1.0)
        }
        // Add highlight stop for sharper edge
        gradientLayer.colors = [highlightColor.cgColor, lightColor.cgColor, darkColor.cgColor]
        gradientLayer.locations = [0.0, 0.15, 1.0] // Adjust location for highlight size
        gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.25); gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.75)
        // --- End Refinement ---

        pieceView.layer.addSublayer(gradientLayer); pieceView.layer.cornerRadius = pieceSize / 2; pieceView.layer.borderWidth = 0.5
        pieceView.layer.borderColor = (player == .black) ? UIColor(white: 0.5, alpha: 0.7).cgColor : UIColor(white: 0.6, alpha: 0.7).cgColor
        pieceView.layer.shadowColor = UIColor.black.cgColor; pieceView.layer.shadowOpacity = 0.4; pieceView.layer.shadowOffset = CGSize(width: 1, height: 2); pieceView.layer.shadowRadius = 2.0; pieceView.layer.masksToBounds = false

        // --- Piece Placement Animation ---
        pieceView.alpha = 0.0 // Start invisible
        pieceView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6) // Start scaled down

        // Ensure removal happens *before* adding subview for animation
        pieceViews[row][col]?.removeFromSuperview()
        boardView.addSubview(pieceView)
        pieceViews[row][col] = pieceView // Update reference

        UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            pieceView.alpha = 1.0
            pieceView.transform = .identity // Animate to normal scale
        }, completion: nil)
        // --- End Animation ---

        // --- Last Move Indicator (will be added separately after placement) ---
        // showLastMoveIndicator(at: Position(row: row, col: col)) // Called from placePiece instead
    }
    
    func showLastMoveIndicator(at position: Position) {
        // Remove previous indicator immediately
        lastMoveIndicatorLayer?.removeFromSuperlayer()
        lastMoveIndicatorLayer = nil

        guard cellSize > 0 else { return }

        let indicatorSize = cellSize * 0.95 // Slightly larger than piece
        let x = boardPadding + CGFloat(position.col) * cellSize - (indicatorSize / 2)
        let y = boardPadding + CGFloat(position.row) * cellSize - (indicatorSize / 2)
        let indicatorFrame = CGRect(x: x, y: y, width: indicatorSize, height: indicatorSize)

        let indicator = CALayer()
        indicator.frame = indicatorFrame
        indicator.cornerRadius = indicatorSize / 2
        indicator.borderWidth = 2.5 // Thicker border for indicator
        indicator.borderColor = UIColor.systemYellow.withAlphaComponent(0.8).cgColor // Yellowish indicator
        indicator.opacity = 0.0 // Start invisible

        boardView.layer.addSublayer(indicator) // Add directly to boardView layer
        self.lastMoveIndicatorLayer = indicator

        // Fade In Animation
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 0.8
        fadeIn.duration = 0.2

        // Fade Out Animation (after a delay)
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.8
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + 0.75 // Start fade out after 0.75 seconds
        fadeOut.duration = 0.5
        fadeOut.fillMode = .forwards // Keep final state
        fadeOut.isRemovedOnCompletion = false // Keep final state

        // Group animations (optional, can just add fadeOut later)
        // For simplicity, let's just fade in and then remove after delay

        indicator.opacity = 0.8 // Set final opacity for fade in
        indicator.add(fadeIn, forKey: "fadeInIndicator")

        // Remove layer after animations complete + buffer
         DispatchQueue.main.asyncAfter(deadline: .now() + 0.75 + 0.5 + 0.1) { [weak self] in
              // Check if this specific layer is still the current one before removing
              if self?.lastMoveIndicatorLayer === indicator {
                   indicator.removeFromSuperlayer()
                   if self?.lastMoveIndicatorLayer === indicator { // Double check after potential async race
                        self?.lastMoveIndicatorLayer = nil
                   }
              }
         }
    }

    // --- Game Logic & Interaction ---
    func setupNewGameVariablesOnly() { /* ... */ currentPlayer = .black; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); gameOver = false; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize) }
    func setupNewGame() { /* ... */ print("setupNewGame called. Current Mode: \(currentGameMode)"); gameOver = false; currentPlayer = .black; statusLabel.text = "Black's Turn"; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); boardView.subviews.forEach { $0.removeFromSuperview() }; boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll(); winningLineLayer?.removeFromSuperlayer(); winningLineLayer = nil; lastMoveIndicatorLayer?.removeFromSuperlayer(); lastMoveIndicatorLayer = nil; lastMovePosition = nil; print("setupNewGame: Reset state, cellSize, lastDrawnBoardBounds, removed win/move indicators."); pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); cellSize = 0; lastDrawnBoardBounds = .zero; print("setupNewGame: Reset state, cellSize, and lastDrawnBoardBounds.");
        if turnIndicatorBorderLayer == nil {
             setupTurnIndicatorBorder() // Create if first game
        }
        updateTurnIndicator() // Set color for Black's turn
        // --- End Indicator Update ---

        view.setNeedsLayout() }
    func calculateCellSize() -> CGFloat { /* ... */ guard boardView.bounds.width > 0, boardView.bounds.height > 0 else { return 0 }; let boardDimension = min(boardView.bounds.width, boardView.bounds.height) - (boardPadding * 2); guard boardSize > 1 else { return boardDimension }; let size = boardDimension / CGFloat(boardSize - 1); return max(0, size) }
    func addTapGestureRecognizer() { /* ... */ guard let currentBoardView = boardView else { print("FATAL ERROR: boardView outlet is NIL..."); return }; print("addTapGestureRecognizer attempting to add..."); currentBoardView.gestureRecognizers?.forEach { currentBoardView.removeGestureRecognizer($0) }; let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))); currentBoardView.addGestureRecognizer(tap); print("--> Tap Gesture Recognizer ADDED.") }
    
    // --- NEW: Function to Shake the Board ---
    func shakeBoard() {
        print("Shaking board for invalid move")
        // Create animation only once for performance
        if shakeAnimation == nil {
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.duration = 0.07
            animation.repeatCount = 3 // Number of shakes
            animation.autoreverses = true
            // --- FIX: Explicitly use CGFloat for the offset ---
            animation.fromValue = NSNumber(value: boardView.center.x - CGFloat(6)) // Shake distance
            animation.toValue = NSNumber(value: boardView.center.x + CGFloat(6))
            // --- End FIX ---
            shakeAnimation = animation
        }

        // Check if boardView still exists and has a layer before adding animation
        if let shake = shakeAnimation, boardView != nil {
            boardView.layer.add(shake, forKey: "position.x")
        } else if boardView == nil {
             print("Warning: Tried to shake boardView but it was nil.")
        }
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard currentGameState == .playing else { print("Tap ignored: Not in playing state."); return }
        print("--- handleTap CALLED ---")
        guard !gameOver, cellSize > 0 else { print("Guard FAILED: gameOver=\(gameOver), cellSize=\(cellSize)"); return }
        guard !isAiTurn else { print("Tap ignored: It's AI's turn."); return }
        let location = sender.location(in: boardView); print("Tap location in view: \(location)")
        let playableWidth = boardView.bounds.width - 2 * boardPadding; let playableHeight = boardView.bounds.height - 2 * boardPadding; let tapArea = CGRect(x: boardPadding - cellSize*0.5, y: boardPadding - cellSize*0.5, width: playableWidth + cellSize, height: playableHeight + cellSize)
        guard tapArea.contains(location) else {
            print("Guard FAILED: Tap outside playable area.");
            shakeBoard() // <<-- SHAKE
            return
        }
        let tappedColFloat = (location.x - boardPadding) / cellSize; let tappedRowFloat = (location.y - boardPadding) / cellSize; print("Calculated float coords: (col: \(tappedColFloat), row: \(tappedRowFloat))")
        let colDiff = abs(tappedColFloat - round(tappedColFloat)); let rowDiff = abs(tappedRowFloat - round(tappedRowFloat)); print("Intersection proximity check: colDiff=\(colDiff), rowDiff=\(rowDiff) (Needs < 0.4)")
        guard colDiff < 0.4 && rowDiff < 0.4 else {
            print("Guard FAILED: Tap too far from intersection.");
            shakeBoard() // <<-- SHAKE
            return
        }
        let tappedCol = Int(round(tappedColFloat)); let tappedRow = Int(round(tappedRowFloat)); print("Rounded integer coords: (col: \(tappedCol), row: \(tappedRow))")
        print("Checking bounds (0-\(boardSize-1)): row=\(tappedRow), col=\(tappedCol)")
        guard checkBounds(row: tappedRow, col: tappedCol) else {
            print("Guard FAILED: Tap out of bounds.");
             shakeBoard() // <<-- SHAKE
            return
        }
        print("Checking if empty at [\(tappedRow)][\(tappedCol)]: Current state = \(board[tappedRow][tappedCol])")
        guard board[tappedRow][tappedCol] == .empty else {
            print("Guard FAILED: Cell already occupied.");
            shakeBoard() // <<-- SHAKE
            return
        }
        print("All guards passed. Placing piece..."); placePiece(atRow: tappedRow, col: tappedCol)
    }
    
    func placePiece(atRow row: Int, col: Int) {
        guard currentGameState == .playing else { return }
        let pieceState: CellState = (currentPlayer == .black) ? .black : .white; board[row][col] = pieceState

        // Draw the piece (includes animation now)
        drawPiece(atRow: row, col: col, player: currentPlayer)

        // --- Show Last Move Indicator ---
        let currentPosition = Position(row: row, col: col)
        self.lastMovePosition = currentPosition // Store position
        // Delay showing indicator slightly to let piece animation start
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
             self?.showLastMoveIndicator(at: currentPosition)
        }
        // --- End Show Indicator ---


        if let winningPositions = findWinningLine(playerState: pieceState, lastRow: row, lastCol: col) {
            gameOver = true; updateTurnIndicator(); let winner = (pieceState == .black) ? "Black" : "White"; let message = "\(winner) Wins!"
            statusLabel.text = message; print(message); drawWinningLine(positions: winningPositions)
            showGameOverOverlay(message: message); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer() // Remove indicator immediately on win
            lastMoveIndicatorLayer = nil
        } else if isBoardFull() {
            gameOver = true; updateTurnIndicator(); statusLabel.text = "Draw!"; print("Draw!")
            showGameOverOverlay(message: "Draw!"); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer() // Remove indicator immediately on draw
            lastMoveIndicatorLayer = nil
        } else {
            switchPlayer()
        }
    }
    func findWinningLine(playerState: CellState, lastRow: Int, lastCol: Int) -> [Position]? { /* ... */ guard playerState != .empty else { return nil }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var linePositions: [Position] = [Position(row: lastRow, col: lastCol)]; for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)) } else { break } }; for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)) } else { break } }; if linePositions.count >= 5 { linePositions.sort { ($0.row, $0.col) < ($1.row, $1.col) }; return Array(linePositions.prefix(5)) } }; return nil }
    func switchPlayer() { /* ... */ guard !gameOver else { return }; let previousPlayer = currentPlayer; currentPlayer = (currentPlayer == .black) ? .white : .black; statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn"; updateTurnIndicator(); if isAiTurn { view.isUserInteractionEnabled = false; statusLabel.text = "Computer (\(selectedDifficulty)) Turn..."; print("Switching to AI (\(selectedDifficulty)) turn..."); DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in guard let self = self else { return }; if !self.gameOver && self.isAiTurn { self.performAiTurn() } else { print("AI turn skipped (game over or state changed during delay)"); self.view.isUserInteractionEnabled = true } } } else { print("Switching to Human turn..."); view.isUserInteractionEnabled = true } }

    // --- ADD THIS FUNCTION BACK ---
    // Helper for Hard AI - Check for moves creating a Four threat
    // Checks if placing a piece at 'potentialPosition' for 'player'
    // creates any immediate four-in-a-row threat (like _PPPP, P_PPP etc.)
    func findMakeFourMove(for player: Player, potentialPosition: Position, on boardToCheck: [[CellState]]) -> Bool {
        let playerState: CellState = (player == .black) ? .black : .white
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

        // Ensure the position is valid and empty before simulation
        guard checkBounds(row: potentialPosition.row, col: potentialPosition.col) &&
              boardToCheck[potentialPosition.row][potentialPosition.col] == .empty else {
            return false
        }

        // Temporarily place the piece to check the resulting pattern
        var tempBoard = boardToCheck
        tempBoard[potentialPosition.row][potentialPosition.col] = playerState

        for (dr, dc) in directions {
            // Check windows of 5 centered around the placed piece
            for offset in -4...0 { // Start checking from 4 steps before to include all 5-windows containing the new piece
                let startRow = potentialPosition.row + dr * offset
                let startCol = potentialPosition.col + dc * offset

                // Check bounds for BOTH start and end of the 5-window
                guard checkBounds(row: startRow, col: startCol) else { continue }
                guard checkBounds(row: startRow + dr*4, col: startCol + dc*4) else { continue }

                // Now check the pattern within the valid window
                var playerCount = 0
                var opponentFound = false
                for i in 0..<5 {
                    let currentState = tempBoard[startRow + dr*i][startCol + dc*i]
                    if currentState == playerState {
                        playerCount += 1
                    } else if currentState != .empty { // Opponent piece
                        opponentFound = true
                        break // Stop checking this window if opponent is present
                    }
                }

                // If we found exactly 4 player pieces AND no opponent pieces, it's a 'four' threat
                if !opponentFound && playerCount == 4 {
                    print("findMakeFourMove: Found four-threat at window starting \(startRow),\(startCol) for offset \(offset), direction (\(dr),\(dc))")
                    return true
                }
            } // End offset loop
        } // End directions loop
        return false // No immediate four-threat created
    }
    // --- AI Logic ---
    func performAiTurn() {
       guard !gameOver else { view.isUserInteractionEnabled = true; return }
       print("AI Turn (\(selectedDifficulty)): Performing move...")
       switch selectedDifficulty {
       case .easy: performSimpleAiMove()
       case .medium: performStandardAiMove()
       case .hard: performHardAiMove() // Calls the new V5 logic
       }
       // ... (Interaction re-enabling logic remains the same) ...
        DispatchQueue.main.async { if !self.gameOver && !self.isAiTurn { self.view.isUserInteractionEnabled = true; print("AI Turn (\(self.selectedDifficulty)): Re-enabled user interaction.") } else if self.gameOver { self.view.isUserInteractionEnabled = true; print("AI Turn (\(self.selectedDifficulty)): Game Over, re-enabled user interaction.") } }
   }
    // RENAME performEasyAiMove -> performSimpleAiMove
    func performSimpleAiMove() { /* ... unchanged ... */
        let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Easy: No empty cells left."); return }; let humanPlayer: Player = (aiPlayer == .black) ? .white : .black; for cell in emptyCells { if checkPotentialWin(player: aiPlayer, position: cell) { print("AI Easy: Found winning move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }; for cell in emptyCells { if checkPotentialWin(player: humanPlayer, position: cell) { print("AI Easy: Found blocking move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }; var makeTwoMoves: [Position] = []; for cell in emptyCells { if findMakeTwoMove(for: aiPlayer, potentialPosition: cell, on: self.board) != nil { makeTwoMoves.append(cell) } }; if let makeTwoMove = makeTwoMoves.randomElement() { print("AI Easy: Found 'Make Two' move at \(makeTwoMove)"); placeAiPieceAndEndTurn(at: makeTwoMove); return }; let adjacentCells = findAdjacentEmptyCells(); if let targetCell = adjacentCells.randomElement() { print("AI Easy: Playing random adjacent move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return }; if let targetCell = emptyCells.randomElement() { print("AI Easy: Playing completely random move at \(targetCell)"); placeAiPieceAndEndTurn(at: targetCell); return }; print("AI Easy: Could not find any valid move.")
    }
    // RENAME performMediumAiMove -> performStandardAiMove
    func performStandardAiMove() { /* ... unchanged ... */
         let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Medium: No empty cells left."); return }; let humanPlayer: Player = (aiPlayer == .black) ? .white : .black; for cell in emptyCells { if checkPotentialWin(player: aiPlayer, position: cell) { print("AI Medium: Found winning move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }; for cell in emptyCells { if checkPotentialWin(player: humanPlayer, position: cell) { print("AI Medium: Found blocking win move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }; var creatingOpenThreeMoves: [Position] = []; for cell in emptyCells { if findSpecificOpenThreeMove(for: aiPlayer, potentialPosition: cell, on: self.board) { creatingOpenThreeMoves.append(cell) } }; if let createMove = creatingOpenThreeMoves.randomElement() { print("AI Medium: Found creating Open Three move at \(createMove)"); placeAiPieceAndEndTurn(at: createMove); return }; var blockingOpenThreeMoves: [Position] = []; for cell in emptyCells { if findSpecificOpenThreeMove(for: humanPlayer, potentialPosition: cell, on: self.board) { blockingOpenThreeMoves.append(cell) } }; if let blockMove = blockingOpenThreeMoves.randomElement() { print("AI Medium: Found blocking Open Three move at \(blockMove)"); placeAiPieceAndEndTurn(at: blockMove); return }; var makeTwoMoves: [Position] = []; for cell in emptyCells { if findMakeTwoMove(for: aiPlayer, potentialPosition: cell, on: self.board) != nil { makeTwoMoves.append(cell) } }; if let makeTwoMove = makeTwoMoves.randomElement() { print("AI Medium: Found 'Make Two' move at \(makeTwoMove)"); placeAiPieceAndEndTurn(at: makeTwoMove); return }; print("AI Medium: No better move found. Falling back to Simple logic."); performSimpleAiMove()
    }
    func performHardAiMove() {
        let emptyCells = findEmptyCells(); if emptyCells.isEmpty { print("AI Hard: No empty cells left."); return }
        let humanPlayer: Player = (aiPlayer == .black) ? .white : .black

        print("AI Hard (V5 - Pattern Focus): Evaluating moves...")

        // --- AI Priorities ---

        // 1. Win? (AI immediate win)
        for cell in emptyCells { if checkPotentialWin(player: aiPlayer, position: cell) { print("AI Hard: Found winning move at \(cell)"); placeAiPieceAndEndTurn(at: cell); return } }

        // 2. Block Win? (Human immediate win)
        var mandatoryBlockMoves: [Position] = []
        for cell in emptyCells { if checkPotentialWin(player: humanPlayer, position: cell) { mandatoryBlockMoves.append(cell) } }
        if let blockMove = mandatoryBlockMoves.randomElement() { // Block one randomly if multiple exist
            print("AI Hard: Found blocking win move at \(blockMove)")
            placeAiPieceAndEndTurn(at: blockMove); return
        }

        // --- NEW Priority 3: Create Four Threat (Offensive) ---
        // Prioritize making ANY four, even if blockable immediately
        var makeFourMoves: [Position] = []
        for cell in emptyCells { if findMakeFourMove(for: aiPlayer, potentialPosition: cell, on: self.board) { makeFourMoves.append(cell) } }
        if let createFourMove = makeFourMoves.randomElement() {
            print("AI Hard: Found creating Four move at \(createFourMove)")
            placeAiPieceAndEndTurn(at: createFourMove); return
        }

        // --- NEW Priority 4: Block Opponent's Four Threat (Defensive) ---
        // Find ANY move that opponent could make to create a four
        var blockFourMoves: [Position] = []
        for cell in emptyCells { if findMakeFourMove(for: humanPlayer, potentialPosition: cell, on: self.board) { blockFourMoves.append(cell) } }
        if let blockFourMove = blockFourMoves.randomElement() {
            print("AI Hard: Found blocking opponent Four move at \(blockFourMove)")
            placeAiPieceAndEndTurn(at: blockFourMove); return
        }

        // 5. Create Own Open Three? (From Medium Logic)
        var creatingOpenThreeMoves: [Position] = [];
        for cell in emptyCells { if findSpecificOpenThreeMove(for: aiPlayer, potentialPosition: cell, on: self.board) { creatingOpenThreeMoves.append(cell) } }
        if let createMove = creatingOpenThreeMoves.randomElement() { print("AI Hard: Found creating Open Three move at \(createMove)"); placeAiPieceAndEndTurn(at: createMove); return }

        // 6. Block Opponent's Open Three? (From Medium Logic)
        var blockingOpenThreeMoves: [Position] = [];
        for cell in emptyCells { if findSpecificOpenThreeMove(for: humanPlayer, potentialPosition: cell, on: self.board) { blockingOpenThreeMoves.append(cell) } }
        if let blockMove = blockingOpenThreeMoves.randomElement() { print("AI Hard: Found blocking Open Three move at \(blockMove)"); placeAiPieceAndEndTurn(at: blockMove); return }

        // --- NEW Priority 7: Center/Adjacent Preference Fallback ---
        // Prefer moves adjacent to existing pieces or near the center
        let adjacentCells = findAdjacentEmptyCells()
        var preferredMoves: [Position] = []
        let center = boardSize / 2
        let maxDist = center / 2 // Define a 'near center' radius

        for cell in adjacentCells {
            let distFromCenter = max(abs(cell.row - center), abs(cell.col - center))
            if distFromCenter <= maxDist {
                preferredMoves.append(cell) // Prefer adjacent moves near center
            }
        }
        // If no preferred moves found among adjacent, just use any adjacent
        if preferredMoves.isEmpty && !adjacentCells.isEmpty {
            preferredMoves = adjacentCells
        }
        // If preferred (adjacent near center or just adjacent) moves exist, pick one
        if let preferredMove = preferredMoves.randomElement() {
            print("AI Hard: Playing preferred adjacent/center move at \(preferredMove)")
            placeAiPieceAndEndTurn(at: preferredMove); return
        }

        // 8. Fallback to Easy AI Logic (Make Two / Random) - Should be less frequent now
        print("AI Hard: No high-priority or preferred move found. Falling back to Easy logic.")
        performStandardAiMove()
    }
    // Keep pattern checking helpers needed by Easy/Medium
    func checkPattern(pattern: [CellState], startRow: Int, startCol: Int, direction: (dr: Int, dc: Int), on boardToCheck: [[CellState]]) -> Bool { /* ... */ for i in 0..<pattern.count { let r = startRow + direction.dr * i; let c = startCol + direction.dc * i; if !checkBounds(row: r, col: c) || boardToCheck[r][c] != pattern[i] { return false } }; return true }
    func findSpecificOpenThreeMove(for player: Player, potentialPosition: Position, on boardToCheck: [[CellState]]) -> Bool { /* ... */ let playerState: CellState = (player == .black) ? .black : .white; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; guard checkBounds(row: potentialPosition.row, col: potentialPosition.col) && boardToCheck[potentialPosition.row][potentialPosition.col] == .empty else { return false }; for (dr, dc) in directions { if checkPattern(pattern: [.empty, playerState, playerState, playerState, .empty], startRow: potentialPosition.row, startCol: potentialPosition.col, direction: (dr, dc), on: boardToCheck) { return true }; if checkPattern(pattern: [.empty, playerState, playerState, playerState, .empty], startRow: potentialPosition.row - dr*4, startCol: potentialPosition.col - dc*4, direction: (dr, dc), on: boardToCheck) { return true } }; return false }
    func findMakeTwoMove(for player: Player, potentialPosition: Position, on boardToCheck: [[CellState]]) -> Position? { /* ... */ let playerState: CellState = (player == .black) ? .black : .white; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { if checkPattern(pattern: [.empty, playerState, .empty], startRow: potentialPosition.row - dr*2, startCol: potentialPosition.col - dc*2, direction: (dr, dc), on: boardToCheck) { return potentialPosition }; if checkPattern(pattern: [.empty, playerState, .empty], startRow: potentialPosition.row, startCol: potentialPosition.col, direction: (dr, dc), on: boardToCheck) { return potentialPosition }; if checkPattern(pattern: [playerState, .empty, .empty], startRow: potentialPosition.row - dr, startCol: potentialPosition.col - dc, direction: (dr, dc), on: boardToCheck) { return potentialPosition }; if checkPattern(pattern: [.empty, .empty, playerState], startRow: potentialPosition.row, startCol: potentialPosition.col, direction: (dr, dc), on: boardToCheck) { return potentialPosition } }; return nil }

    // Core logic helpers (Unchanged)
    func placeAiPieceAndEndTurn(at position: Position) { placePiece(atRow: position.row, col: position.col) }
    func checkPotentialWin(player: Player, position: Position) -> Bool { var tempBoard = self.board; guard checkBounds(row: position.row, col: position.col) && tempBoard[position.row][position.col] == .empty else { return false }; tempBoard[position.row][position.col] = (player == .black) ? .black : .white; return checkForWinOnBoard(boardToCheck: tempBoard, playerState: tempBoard[position.row][position.col], lastRow: position.row, lastCol: position.col) }
    func checkForWinOnBoard(boardToCheck: [[CellState]], playerState: CellState, lastRow: Int, lastCol: Int) -> Bool { guard playerState != .empty else { return false }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var count = 1; for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } }; for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } }; if count >= 5 { return true } }; return false }
    func findEmptyCells() -> [Position] { var emptyPositions: [Position] = []; for r in 0..<boardSize { for c in 0..<boardSize { if board[r][c] == .empty { emptyPositions.append(Position(row: r, col: c)) } } }; return emptyPositions }
    func findAdjacentEmptyCells() -> [Position] { var adjacentEmpty = Set<Position>(); let directions = [(-1,-1), (-1,0), (-1,1), (0,-1), (0,1), (1,-1), (1,0), (1,1)]; for r in 0..<boardSize { for c in 0..<boardSize { if board[r][c] != .empty { for (dr, dc) in directions { let nr = r + dr; let nc = c + dc; if checkBounds(row: nr, col: nc) && board[nr][nc] == .empty { adjacentEmpty.insert(Position(row: nr, col: nc)) } } } } }; return Array(adjacentEmpty) }
    struct Position: Hashable { var row: Int; var col: Int }
    func isBoardFull() -> Bool { for row in board { if row.contains(.empty) { return false } }; return true }
    func checkBounds(row: Int, col: Int) -> Bool { return row >= 0 && row < boardSize && col >= 0 && col < boardSize }
    
    func drawWinningLine(positions: [Position]) {
        guard positions.count >= 2 else { return }
        winningLineLayer?.removeFromSuperlayer()
        let path = UIBezierPath()
        let firstPos = positions.first!; let startX = boardPadding + CGFloat(firstPos.col) * cellSize; let startY = boardPadding + CGFloat(firstPos.row) * cellSize; path.move(to: CGPoint(x: startX, y: startY))
        let lastPos = positions.last!; let endX = boardPadding + CGFloat(lastPos.col) * cellSize; let endY = boardPadding + CGFloat(lastPos.row) * cellSize; path.addLine(to: CGPoint(x: endX, y: endY))
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath; shapeLayer.strokeColor = UIColor.red.withAlphaComponent(0.8).cgColor; shapeLayer.lineWidth = 5.0
        shapeLayer.lineCap = .round; shapeLayer.lineJoin = .round; shapeLayer.name = "winningLine"
        shapeLayer.strokeEnd = 0.0 // Start with the line not drawn

        boardView.layer.addSublayer(shapeLayer)
        self.winningLineLayer = shapeLayer

        // --- Animate the line drawing ---
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.duration = 0.5 // Duration for line draw
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Update model layer first
        shapeLayer.strokeEnd = 1.0
        // Add animation
        shapeLayer.add(animation, forKey: "drawLineAnimation")
        // --- End Animation ---

        print("Winning line drawn.")
    }
    
    func getRow(_ r: Int, on boardToCheck: [[CellState]]) -> [CellState] {
        // Check bounds for the row index itself
        guard r >= 0 && r < boardSize else {
             print("Error: getRow called with invalid row index \(r)")
             return [] // Return empty array if index is invalid
        }
        return boardToCheck[r]
    }

    func getColumn(_ c: Int, on boardToCheck: [[CellState]]) -> [CellState] {
         // Check bounds for the column index itself
         guard c >= 0 && c < boardSize else {
             print("Error: getColumn called with invalid column index \(c)")
             return [] // Return empty array if index is invalid
         }
        // Use map safely, assuming boardToCheck has consistent inner array sizes (boardSize)
        // If boardToCheck could be jagged, add more checks.
        return boardToCheck.map { $0[c] }
    }

    func getDiagonals(on boardToCheck: [[CellState]]) -> [[CellState]] {
        var diagonals: [[CellState]] = []
        let n = boardSize // Use the defined boardSize

        // Ensure board is not empty and has expected dimensions before proceeding
        guard !boardToCheck.isEmpty && boardToCheck.count == n && boardToCheck[0].count == n else {
             print("Error: getDiagonals called with invalid board dimensions.")
             return []
        }

        // --- Diagonals (Top-Left to Bottom-Right) ---
        // Start from top row (index 0), moving right
        for c in 0..<n {
            var diag: [CellState] = []
            var r_temp = 0
            var c_temp = c
            while checkBounds(row: r_temp, col: c_temp) { // Use existing checkBounds
                diag.append(boardToCheck[r_temp][c_temp])
                r_temp += 1
                c_temp += 1
            }
            if diag.count >= 5 { diagonals.append(diag) } // Only consider lines long enough to win
        }
         // Start from left column (index 0), moving down (skip row 0 as it's covered above)
        for r in 1..<n {
             var diag: [CellState] = []
             var r_temp = r
             var c_temp = 0
             while checkBounds(row: r_temp, col: c_temp) {
                 diag.append(boardToCheck[r_temp][c_temp])
                 r_temp += 1
                 c_temp += 1
             }
             if diag.count >= 5 { diagonals.append(diag) }
         }

        // --- Anti-Diagonals (Top-Right to Bottom-Left) ---
         // Start from top row (index 0), moving left
         for c in 0..<n {
             var antiDiag: [CellState] = []
             var r_temp = 0
             var c_temp = c
             while checkBounds(row: r_temp, col: c_temp) {
                 antiDiag.append(boardToCheck[r_temp][c_temp])
                 r_temp += 1 // Move down
                 c_temp -= 1 // Move left
             }
             if antiDiag.count >= 5 { diagonals.append(antiDiag) }
         }
         // Start from right column (index n-1), moving down (skip row 0)
         for r in 1..<n {
              var antiDiag: [CellState] = []
              var r_temp = r
              var c_temp = n - 1
              while checkBounds(row: r_temp, col: c_temp) {
                  antiDiag.append(boardToCheck[r_temp][c_temp])
                  r_temp += 1 // Move down
                  c_temp -= 1 // Move left
              }
              if antiDiag.count >= 5 { diagonals.append(antiDiag) }
          }

        return diagonals
    }

    // --- Reset Button Logic (Unchanged) ---
    @IBAction func resetButtonTapped(_ sender: UIButton) { /* ... */ print("Reset button DOWN"); UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: { sender.transform = CGAffineTransform(scaleX: 0.92, y: 0.92) }, completion: nil); if currentGameState == .playing { print("Resetting game..."); setupNewGame(); if !isAiTurn { view.isUserInteractionEnabled = true } } else { print("Reset tapped while in setup state - doing nothing.") }; sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpInside); sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpOutside); sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchCancel) }
    @IBAction func resetButtonReleased(_ sender: UIButton) { /* ... */ print("Reset button RELEASED"); UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: { sender.transform = .identity }, completion: { _ in sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside); sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside); sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)}) }

} // End of ViewController class
